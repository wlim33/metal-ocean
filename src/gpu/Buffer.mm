#import "gpu/Buffer.h"
#import "gpu/MetalContext.h"
#import <Metal/Metal.h>

namespace mo {
Buffer make_buffer(const MetalContext& ctx, size_t bytes, bool shared) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    MTLResourceOptions opt = shared ? MTLResourceStorageModeShared : MTLResourceStorageModePrivate;
    id<MTLBuffer> b = [dev newBufferWithLength:bytes options:opt];
    Buffer out;
    out.handle = (__bridge_retained void*)b;
    out.size = bytes;
    out.cpu_ptr = shared ? b.contents : nullptr;
    return out;
}
void destroy_buffer(Buffer& b) {
    if (b.handle) { id<MTLBuffer> bb = (__bridge_transfer id<MTLBuffer>)b.handle; (void)bb; }
    b = {};
}
}
