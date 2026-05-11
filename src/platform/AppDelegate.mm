#import "AppDelegate.h"
#import "platform/OceanView.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import <Metal/Metal.h>

@implementation AppDelegate {
    OceanView* _view;
    mo::MetalContext _ctx;
    mo::PipelineCache _cache;
}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    _ctx = mo::create_metal_context();

    NSRect frame = NSMakeRect(100, 100, 1280, 720);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                             | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    _view = [[OceanView alloc] initWithFrame:frame
                                     device:(__bridge id<MTLDevice>)_ctx.device];
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _view.clearColor = MTLClearColorMake(0.02, 0.05, 0.10, 1.0);
    _view.preferredFramesPerSecond = 60;

    mo::RenderPSODesc fs_desc;
    fs_desc.vertex_fn = "fs_triangle_vs";
    fs_desc.fragment_fn = "fs_clear_fs";
    void* pso = _cache.render_pso(_ctx, fs_desc);

    [_view setFrameRenderer:^(id<MTLCommandBuffer> cb, MTLRenderPassDescriptor* rp) {
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
    }];

    self.window.contentView = _view;
    self.window.title = @"metal-ocean";
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { return YES; }
@end
