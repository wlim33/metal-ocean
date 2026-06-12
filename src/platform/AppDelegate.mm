#import "AppDelegate.h"
#import "platform/OceanView.h"
#import "platform/InputBridge.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "core/App.h"
#import "ui/ImGuiBackend.h"
#import "ui/DebugPanel.h"
#import "render/OceanRenderer.h"
#import "render/SkyRenderer.h"
#import "render/SprayRenderer.h"
#import "ocean/ProjectedGrid.h"
#import "ocean/Simulation.h"
#import "bench/BenchmarkHarness.h"
#import "bench/BenchCameraPath.h"
#import "bench/CounterSampler.h"
#import <Metal/Metal.h>
#include <memory>
#include <fstream>
#include <sstream>
#include <chrono>
#include <cstdlib>

extern double mo_g_drawable_wait_ms;

@implementation AppDelegate {
    OceanView* _view;
    mo::MetalContext _ctx;
    mo::PipelineCache _cache;
    mo::InputBridge _input;
    std::unique_ptr<mo::App> _app;
    mo::ImGuiBackend _imgui;
    mo::OceanRenderer _ocean;
    mo::SkyRenderer _sky;
    mo::SprayRenderer _spray;
    mo::Simulation _sim;
    mo::BenchmarkHarness _bench;
    int _frame_index;
    // Profiling (MO_PROF_OUT env; MO_PROF_SPLIT=1 per-stage split).
    mo::CounterSampler _samplers[4];
    std::ofstream _prof;
    bool _prof_on;
    bool _prof_split;
}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    _ctx = mo::create_metal_context();
    NSArray<NSString*>* args = [[NSProcessInfo processInfo] arguments];
    std::string toml = "";
    std::vector<std::string> overrides;
    for (NSUInteger i = 1; i < args.count; ++i) {
        NSString* a = args[i];
        if ([a isEqualToString:@"--config"] && i + 1 < args.count) {
            std::ifstream in([args[i+1] UTF8String]);
            std::stringstream ss; ss << in.rdbuf(); toml = ss.str(); ++i;
        } else if ([a isEqualToString:@"--set"] && i + 1 < args.count) {
            overrides.emplace_back([args[i+1] UTF8String]); ++i;
        }
    }
    if (toml.empty()) {
        NSString* defp = [[NSBundle mainBundle] pathForResource:@"default-config" ofType:@"toml"];
        if (defp) {
            std::ifstream in([defp UTF8String]);
            std::stringstream ss; ss << in.rdbuf(); toml = ss.str();
        }
    }
    auto load = mo::load_config_from_string(toml);
    load = mo::apply_overrides(std::move(load), overrides);
    _app = std::make_unique<mo::App>(load.config);

    NSRect frame = NSMakeRect(100, 100, 1280, 720);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                             | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                backing:NSBackingStoreBuffered defer:NO];
    _view = [[OceanView alloc] initWithFrame:frame
                                     device:(__bridge id<MTLDevice>)_ctx.device];
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _view.clearColor = MTLClearColorMake(0.02, 0.05, 0.10, 1.0);
    [_view setCommandQueue:(__bridge id<MTLCommandQueue>)_ctx.queue];
    [_view setInputBridge:&_input];
    _app->camera().set_aspect(1280.0f / 720.0f);

    _imgui.init(_ctx, (__bridge void*)_view);
    _ocean.init(_ctx, _cache);
    _sky.init(_ctx, _cache);
    _spray.init(_ctx, _cache);
    _sim.init(_ctx, _cache, _app->config());
    _bench.start(_app->config(), mo::config_hash(_app->config()));
    _frame_index = 0;

    _prof_on = false;
    _prof_split = getenv("MO_PROF_SPLIT") && atoi(getenv("MO_PROF_SPLIT")) != 0;
    if (const char* pp = getenv("MO_PROF_OUT")) {
        bool ok = true;
        for (auto& s : _samplers) ok = s.init(_ctx) && ok;
        if (ok) {
            _prof.open(pp);
            _prof << "frame,cpu_ms,wait_ms,grid_ms,upload_ms,encode_ms,gpu_ms,"
                     "comp_ms,spec_ms,fft_ms,post_ms,"
                     "sky_v,sky_f,ocean_v,ocean_f,imgui_v,imgui_f,rend_v,rend_f\n";
            _prof_on = true;
        } else {
            fprintf(stderr, "[prof] GPU counter sampling unsupported on this device\n");
        }
    }

    __weak AppDelegate* weakSelf = self;
    [_view setFrameRenderer:^(id<MTLCommandBuffer> cb, MTLRenderPassDescriptor* rp) {
        AppDelegate* self2 = weakSelf; if (!self2) return;
        if (self2->_bench.active())
            mo::apply_bench_path(self2->_app->camera(),
                self2->_app->config().bench.camera_path,
                self2->_bench.current_frame());
        auto ms_since = [](std::chrono::steady_clock::time_point t0) {
            return std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - t0).count();
        };
        auto tb0 = std::chrono::steady_clock::now();

        // Benchmarks measure the renderer, not the debug UI.
        const bool noui = self2->_bench.active();
        // WantCaptureMouse from the previous ImGui frame gates this frame's
        // camera input — the standard one-frame-latency capture pattern.
        self2->_app->handle_input(self2->_input.drain(),
                                  !noui && self2->_imgui.want_capture_mouse());
        self2->_app->update();
        if (!noui) {
            self2->_imgui.begin_frame((__bridge void*)self2->_view);
            mo::draw_debug_panel(*self2->_app);
        }

        mo::ProjectedGridParams pg;
        pg.cols = self2->_app->config().grid_cols;
        pg.rows = self2->_app->config().grid_rows;
        pg.displacement_range_m = self2->_app->config().displacement_range_m;
        auto tg0 = std::chrono::steady_clock::now();
        auto grid = mo::build_projected_grid(
            self2->_app->camera().view(),
            self2->_app->camera().proj(),
            self2->_app->camera().position(), pg);
        double grid_ms = ms_since(tg0);
        auto tu0 = std::chrono::steady_clock::now();
        self2->_ocean.upload_grid(self2->_ctx, grid, self2->_frame_index);
        double upload_ms = ms_since(tu0);

        self2->_sky.bake_cubemap_if_dirty(self2->_ctx, (__bridge void*)cb, self2->_app->config());
        self2->_ocean.bake_foam_detail_if_needed(self2->_ctx, (__bridge void*)cb, self2->_cache);
        self2->_sim.rebuild_if_dirty(self2->_ctx, self2->_app->config());
        self2->_sim.begin_frame((float)self2->_app->clock().delta_seconds(),
                                self2->_app->config());

        const int slot = self2->_frame_index % 4;
        mo::CounterSampler* smp = self2->_prof_on ? &self2->_samplers[slot] : nullptr;
        id<MTLCounterSampleBuffer> sb = smp
            ? (__bridge id<MTLCounterSampleBuffer>)smp->sample_buffer() : nil;
        int used = 0;
        float sim_time = (float)self2->_app->clock().total_seconds();
        auto te0 = std::chrono::steady_clock::now();

        auto draw_scene = [&](id<MTLRenderCommandEncoder> enc) {
            // Painter's order: sky first, ocean over it. The memoryless depth
            // attachment exists for transparent layers (spume tests it); among the
            // opaque layers the TBDR still only shades the last
            // opaque write per pixel, so the covered sky costs nothing.
            self2->_sky.encode_full_screen((__bridge void*)enc, self2->_app->camera(), self2->_app->config());
            self2->_ocean.encode((__bridge void*)enc, self2->_app->camera(),
                self2->_app->config(), self2->_sim.data(), self2->_sim.count(),
                self2->_sky, self2->_frame_index, self2->_app->debug_view);
            self2->_spray.encode_draw((__bridge void*)enc, self2->_app->camera(), self2->_app->config());
        };
        auto encode_mips = [&]() {
            id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
            self2->_sim.encode_mipgen((__bridge void*)blit, self2->_app->config());
            self2->_spray.encode_counter_reset((__bridge void*)blit);
            [blit endEncoding];
        };

        if (!smp) {
            id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
            self2->_sim.encode((__bridge void*)ce, sim_time, self2->_app->config());
            self2->_spray.encode_compute((__bridge void*)ce, self2->_frame_index,
                                         (float)self2->_app->clock().delta_seconds(),
                                         self2->_app->config(), self2->_app->camera(),
                                         self2->_sim.data(), self2->_sim.count());
            [ce endEncoding];
            encode_mips();
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            draw_scene(enc);
            if (!noui) self2->_imgui.render((__bridge void*)cb, (__bridge void*)rp, (__bridge void*)enc);
            [enc endEncoding];
        } else if (!self2->_prof_split) {
            // Same encoder structure as the unprofiled path, plus counters.
            MTLComputePassDescriptor* cpd = [MTLComputePassDescriptor computePassDescriptor];
            cpd.sampleBufferAttachments[0].sampleBuffer = sb;
            cpd.sampleBufferAttachments[0].startOfEncoderSampleIndex = 0;
            cpd.sampleBufferAttachments[0].endOfEncoderSampleIndex   = 1;
            id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoderWithDescriptor:cpd];
            self2->_sim.encode((__bridge void*)ce, sim_time, self2->_app->config());
            self2->_spray.encode_compute((__bridge void*)ce, self2->_frame_index,
                                         (float)self2->_app->clock().delta_seconds(),
                                         self2->_app->config(), self2->_app->camera(),
                                         self2->_sim.data(), self2->_sim.count());
            [ce endEncoding];
            encode_mips();
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            rp.sampleBufferAttachments[0].sampleBuffer = sb;
            rp.sampleBufferAttachments[0].startOfVertexSampleIndex   = 2;
            rp.sampleBufferAttachments[0].endOfVertexSampleIndex     = 3;
            rp.sampleBufferAttachments[0].startOfFragmentSampleIndex = 4;
            rp.sampleBufferAttachments[0].endOfFragmentSampleIndex   = 5;
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            draw_scene(enc);
            if (!noui) self2->_imgui.render((__bridge void*)cb, (__bridge void*)rp, (__bridge void*)enc);
            [enc endEncoding];
            used = 6;
        } else {
            // Split mode: one compute encoder per sim stage, one render encoder
            // per layer. Attribution only — encoder overhead and tile
            // load/store round-trips inflate the absolute numbers.
            for (int stage = 0; stage < 3; ++stage) {
                MTLComputePassDescriptor* cpd = [MTLComputePassDescriptor computePassDescriptor];
                cpd.sampleBufferAttachments[0].sampleBuffer = sb;
                cpd.sampleBufferAttachments[0].startOfEncoderSampleIndex = stage * 2;
                cpd.sampleBufferAttachments[0].endOfEncoderSampleIndex   = stage * 2 + 1;
                id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoderWithDescriptor:cpd];
                self2->_sim.encode_stage((__bridge void*)ce, stage, sim_time, self2->_app->config());
                if (stage == 2) {
                    self2->_spray.encode_compute((__bridge void*)ce, self2->_frame_index,
                                                 (float)self2->_app->clock().delta_seconds(),
                                                 self2->_app->config(), self2->_app->camera(),
                                                 self2->_sim.data(), self2->_sim.count());
                }
                [ce endEncoding];
            }
            encode_mips();
            auto attach = [&](MTLRenderPassDescriptor* d, int base, bool first) {
                d.colorAttachments[0].storeAction = MTLStoreActionStore;
                if (!first) d.colorAttachments[0].loadAction = MTLLoadActionLoad;
                d.sampleBufferAttachments[0].sampleBuffer = sb;
                d.sampleBufferAttachments[0].startOfVertexSampleIndex   = base;
                d.sampleBufferAttachments[0].endOfVertexSampleIndex     = base + 1;
                d.sampleBufferAttachments[0].startOfFragmentSampleIndex = base + 2;
                d.sampleBufferAttachments[0].endOfFragmentSampleIndex   = base + 3;
            };
            auto render_layer = [&](MTLRenderPassDescriptor* d, void (^body)(id<MTLRenderCommandEncoder>)) {
                id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:d];
                body(enc);
                [enc endEncoding];
            };
            MTLRenderPassDescriptor* rp2 = (MTLRenderPassDescriptor*)[rp copy];
            attach(rp, 6, true);
            attach(rp2, 10, false);
            render_layer(rp, ^(id<MTLRenderCommandEncoder> enc) {
                self2->_sky.encode_full_screen((__bridge void*)enc, self2->_app->camera(), self2->_app->config());
            });
            render_layer(rp2, ^(id<MTLRenderCommandEncoder> enc) {
                self2->_ocean.encode((__bridge void*)enc, self2->_app->camera(),
                    self2->_app->config(), self2->_sim.data(), self2->_sim.count(),
                    self2->_sky, self2->_frame_index, self2->_app->debug_view);
                self2->_spray.encode_draw((__bridge void*)enc, self2->_app->camera(), self2->_app->config());
            });
            if (!noui) {
                MTLRenderPassDescriptor* rp3 = (MTLRenderPassDescriptor*)[rp copy];
                attach(rp3, 14, false);
                render_layer(rp3, ^(id<MTLRenderCommandEncoder> enc) {
                    self2->_imgui.render((__bridge void*)cb, (__bridge void*)rp3, (__bridge void*)enc);
                });
            }
            used = 18;
        }
        double encode_ms = ms_since(te0);
        int fidx = self2->_frame_index;
        self2->_frame_index++;
        double wait_ms = mo_g_drawable_wait_ms;
        double cpu_ms = ms_since(tb0);
        bool split = self2->_prof_split;

        [cb addCompletedHandler:^(id<MTLCommandBuffer> b) {
            double gpu_ms = (b.GPUEndTime - b.GPUStartTime) * 1000.0;
            self2->_bench.record({ self2->_bench.current_frame(), cpu_ms, gpu_ms, wait_ms });
            if (smp && used > 0 && self2->_prof.is_open()) {
                id<MTLCounterSampleBuffer> rsb = (__bridge id<MTLCounterSampleBuffer>)smp->sample_buffer();
                NSData* data = [rsb resolveCounterRange:NSMakeRange(0, (NSUInteger)used)];
                auto* ts = (const MTLCounterResultTimestamp*)data.bytes;
                auto delta = [&](int a, int bI) -> double {
                    if (!ts || ts[a].timestamp == MTLCounterErrorValue ||
                        ts[bI].timestamp == MTLCounterErrorValue) return -1.0;
                    return (double)(ts[bI].timestamp - ts[a].timestamp) / 1e6;
                };
                double comp=0, spec=0, fft=0, post=0,
                       sky_v=0, sky_f=0, oc_v=0, oc_f=0, im_v=0, im_f=0, rv=0, rf=0;
                if (!split) {
                    comp = delta(0,1); rv = delta(2,3); rf = delta(4,5);
                } else {
                    spec = delta(0,1); fft = delta(2,3); post = delta(4,5);
                    sky_v = delta(6,7);  sky_f = delta(8,9);
                    oc_v = delta(10,11); oc_f = delta(12,13);
                    im_v = delta(14,15); im_f = delta(16,17);
                }
                self2->_prof << fidx << ',' << cpu_ms << ',' << wait_ms << ','
                    << grid_ms << ',' << upload_ms << ',' << encode_ms << ',' << gpu_ms << ','
                    << comp << ',' << spec << ',' << fft << ',' << post << ','
                    << sky_v << ',' << sky_f << ',' << oc_v << ',' << oc_f << ','
                    << im_v << ',' << im_f << ',' << rv << ',' << rf << '\n';
                self2->_prof.flush();
            }
            if (self2->_bench.should_exit()) {
                dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
            }
        }];
    }];

    self.window.contentView = _view;
    self.window.title = @"metal-ocean";
    [self.window makeFirstResponder:_view];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)s { return YES; }
@end
