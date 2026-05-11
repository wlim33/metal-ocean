#pragma once
#include <cstddef>
namespace mo {
struct MetalContext;

struct Buffer {
    void*  handle = nullptr;   // id<MTLBuffer>
    size_t size = 0;
    void*  cpu_ptr = nullptr;  // valid for shared/managed
};

Buffer make_buffer(const MetalContext& ctx, size_t bytes, bool shared = true);
void   destroy_buffer(Buffer& b);
}
