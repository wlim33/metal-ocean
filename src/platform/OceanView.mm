#import "platform/OceanView.h"

@implementation OceanView {
    void (^_render)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*);
}

- (BOOL)acceptsFirstResponder { return YES; }
- (void)setFrameRenderer:(void (^)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*))block {
    _render = [block copy];
}

- (void)drawRect:(NSRect)dirty {
    if (!_render) return;
    id<MTLCommandQueue> q = [self.device newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLRenderPassDescriptor* rp = self.currentRenderPassDescriptor;
    if (rp) _render(cb, rp);
    if (self.currentDrawable) [cb presentDrawable:self.currentDrawable];
    [cb commit];
}
@end
