#pragma once
#ifdef __OBJC__
@protocol MTLDevice;
@protocol MTLCommandQueue;
#endif

namespace mo {
struct MetalContext {
    void* device = nullptr;        // id<MTLDevice>
    void* queue  = nullptr;        // id<MTLCommandQueue>
    void* library = nullptr;       // id<MTLLibrary> (default.metallib)
};

MetalContext create_metal_context();
}
