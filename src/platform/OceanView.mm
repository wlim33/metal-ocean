#import "platform/OceanView.h"
#include <chrono>

// Profiling: time spent blocked acquiring the drawable this frame.
double mo_g_drawable_wait_ms = 0.0;

@implementation OceanView {
    void (^_render)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*);
    id<MTLCommandQueue> _queue;
    mo::InputBridge* _bridge;
    BOOL _dragging;
}

- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device];
    if (self) {
        self.delegate = self;
        self.enableSetNeedsDisplay = NO;
        self.paused = NO;
        // Memoryless depth: lives in tile memory only (zero bandwidth).
        // Ocean writes it, spume tests it; cleared each pass, never stored.
        self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        self.depthStencilStorageMode = MTLStorageModeMemoryless;
        self.clearDepth = 1.0;
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

- (void)setInputBridge:(mo::InputBridge*)bridge {
    _bridge = bridge;
}

- (void)mouseDown:(NSEvent*)e {
    _dragging = YES;
    if (_bridge) { mo::InputEvent ev{}; ev.kind = mo::InputKind::MouseDown; ev.button = 0; _bridge->push(ev); }
}

- (void)mouseUp:(NSEvent*)e {
    _dragging = NO;
    if (_bridge) { mo::InputEvent ev{}; ev.kind = mo::InputKind::MouseUp; ev.button = 0; _bridge->push(ev); }
}

- (void)mouseDragged:(NSEvent*)e {
    if (!_bridge) return;
    mo::InputEvent ev{}; ev.kind = mo::InputKind::MouseMove;
    ev.x = (float)e.deltaX; ev.y = (float)e.deltaY;
    _bridge->push(ev);
}

- (void)scrollWheel:(NSEvent*)e {
    if (!_bridge) return;
    mo::InputEvent ev{}; ev.kind = mo::InputKind::Scroll; ev.scroll = (float)e.scrollingDeltaY * 0.05f;
    _bridge->push(ev);
}

- (void)setFrameSize:(NSSize)s {
    [super setFrameSize:s];
    if (_bridge) {
        mo::InputEvent ev{}; ev.kind = mo::InputKind::Resize;
        ev.width = (int)self.drawableSize.width; ev.height = (int)self.drawableSize.height;
        _bridge->push(ev);
    }
}

// MTKViewDelegate — called by the display link every frame
- (void)drawInMTKView:(MTKView*)view {
    if (!_render || !_queue) return;
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    auto t0 = std::chrono::steady_clock::now();
    MTLRenderPassDescriptor* rp = view.currentRenderPassDescriptor;
    mo_g_drawable_wait_ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - t0).count();
    if (rp) _render(cb, rp);
    if (view.currentDrawable) [cb presentDrawable:view.currentDrawable];
    [cb commit];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    // Handle resize if needed in future tasks
    (void)view; (void)size;
}

@end
