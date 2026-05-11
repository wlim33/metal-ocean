#import "platform/OceanView.h"

@implementation OceanView {
    void (^_render)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*);
    id<MTLCommandQueue> _queue;
}

- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device];
    if (self) {
        self.delegate = self;
        self.enableSetNeedsDisplay = NO;
        self.paused = NO;
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)setCommandQueue:(id<MTLCommandQueue>)queue {
    _queue = queue;
}

- (void)setFrameRenderer:(void (^)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*))block {
    _render = [block copy];
}

// MTKViewDelegate — called by the display link every frame
- (void)drawInMTKView:(MTKView*)view {
    if (!_render || !_queue) return;
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    MTLRenderPassDescriptor* rp = view.currentRenderPassDescriptor;
    if (rp) _render(cb, rp);
    if (view.currentDrawable) [cb presentDrawable:view.currentDrawable];
    [cb commit];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    // Handle resize if needed in future tasks
    (void)view; (void)size;
}

@end
