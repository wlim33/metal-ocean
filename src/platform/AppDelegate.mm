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
#import "ocean/Cascade.h"
#import <Metal/Metal.h>
#include <memory>

@implementation AppDelegate {
    OceanView* _view;
    mo::MetalContext _ctx;
    mo::PipelineCache _cache;
    mo::InputBridge _input;
    std::unique_ptr<mo::App> _app;
    mo::ImGuiBackend _imgui;
    mo::OceanRenderer _ocean;
    mo::SkyRenderer _sky;
    mo::Cascade _c0;
    int _frame_index;
}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    _ctx = mo::create_metal_context();
    auto cfg = mo::load_config_from_string("").config;
    _app = std::make_unique<mo::App>(cfg);

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
    {
        mo::CascadeParams cp;
        cp.N = 256;
        cp.size_m = 50.0f;
        _c0.init(_ctx, _cache, cp);
    }
    _frame_index = 0;

    __weak AppDelegate* weakSelf = self;
    [_view setFrameRenderer:^(id<MTLCommandBuffer> cb, MTLRenderPassDescriptor* rp) {
        AppDelegate* self2 = weakSelf; if (!self2) return;
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
            id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
            mo::CascadeParams cp;
            cp.N = 256; cp.size_m = 50.0f;
            cp.wind_speed_mps = self2->_app->config().wave.wind_speed_mps;
            cp.wind_dir_rad   = self2->_app->config().wave.wind_dir_rad;
            cp.choppiness     = self2->_app->config().wave.choppiness;
            self2->_c0.encode((__bridge void*)ce, (float)self2->_app->clock().total_seconds(), cp);
            [ce endEncoding];
        }
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        self2->_sky.encode_full_screen((__bridge void*)enc, self2->_app->camera(), self2->_app->config());
        self2->_ocean.encode_wireframe((__bridge void*)enc, self2->_app->camera(), self2->_frame_index);
        self2->_imgui.render((__bridge void*)cb, (__bridge void*)rp, (__bridge void*)enc);
        [enc endEncoding];
        self2->_frame_index++;
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
