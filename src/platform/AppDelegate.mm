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
#import "ocean/ProjectedGrid.h"
#import "ocean/Simulation.h"
#import "bench/BenchmarkHarness.h"
#import "bench/BenchCameraPath.h"
#import <Metal/Metal.h>
#include <memory>
#include <fstream>
#include <sstream>

@implementation AppDelegate {
    OceanView* _view;
    mo::MetalContext _ctx;
    mo::PipelineCache _cache;
    mo::InputBridge _input;
    std::unique_ptr<mo::App> _app;
    mo::ImGuiBackend _imgui;
    mo::OceanRenderer _ocean;
    mo::SkyRenderer _sky;
    mo::Simulation _sim;
    mo::BenchmarkHarness _bench;
    int _frame_index;
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
    _sim.init(_ctx, _cache, _app->config());
    _bench.start(_app->config(), mo::config_hash(_app->config()));
    _frame_index = 0;

    __weak AppDelegate* weakSelf = self;
    [_view setFrameRenderer:^(id<MTLCommandBuffer> cb, MTLRenderPassDescriptor* rp) {
        AppDelegate* self2 = weakSelf; if (!self2) return;
        if (self2->_bench.active())
            mo::apply_bench_path(self2->_app->camera(),
                self2->_app->config().bench.camera_path,
                self2->_bench.current_frame());
        self2->_app->handle_input(self2->_input);
        self2->_app->update();
        self2->_imgui.begin_frame((__bridge void*)self2->_view);
        mo::draw_debug_panel(*self2->_app);

        mo::ProjectedGridParams pg;
        pg.cols = self2->_app->config().grid_cols;
        pg.rows = self2->_app->config().grid_rows;
        pg.displacement_range_m = self2->_app->config().displacement_range_m;
        auto grid = mo::build_projected_grid(
            self2->_app->camera().view(),
            self2->_app->camera().proj(),
            self2->_app->camera().position(), pg);
        self2->_ocean.upload_grid(self2->_ctx, grid, self2->_frame_index);

        self2->_sky.bake_cubemap_if_dirty(self2->_ctx, (__bridge void*)cb, self2->_app->config());
        {
            self2->_sim.rebuild_if_dirty(self2->_ctx, self2->_app->config());
            id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
            self2->_sim.encode((__bridge void*)ce, (float)self2->_app->clock().total_seconds(),
                               self2->_app->config());
            [ce endEncoding];
        }
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        self2->_sky.encode_full_screen((__bridge void*)enc, self2->_app->camera(), self2->_app->config());
        self2->_ocean.encode((__bridge void*)enc, self2->_app->camera(),
            self2->_app->config(),
            self2->_sim.data(), self2->_sim.count(),
            self2->_sky, self2->_frame_index, self2->_app->debug_view);
        self2->_imgui.render((__bridge void*)cb, (__bridge void*)rp, (__bridge void*)enc);
        [enc endEncoding];
        self2->_frame_index++;
        [cb addCompletedHandler:^(id<MTLCommandBuffer> b) {
            double gpu_ms = (b.GPUEndTime - b.GPUStartTime) * 1000.0;
            self2->_bench.record({ self2->_bench.current_frame(), 0.0, gpu_ms, 0.0 });
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
