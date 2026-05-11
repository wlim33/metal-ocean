#import "gpu/PipelineCache.h"
#import "gpu/MetalContext.h"
#import <Metal/Metal.h>
#include <cstdio>
#include <cstdlib>

namespace mo {

static void die(const char* msg, NSError* err) {
    fprintf(stderr, "FATAL: %s: %s\n", msg,
            err ? err.localizedDescription.UTF8String : "(no error info)");
    std::exit(1);
}

void* PipelineCache::render_pso(const MetalContext& ctx, const RenderPSODesc& d) {
    std::string key = d.vertex_fn + "|" + d.fragment_fn;
    auto it = render_cache_.find(key);
    if (it != render_cache_.end()) return it->second;

    id<MTLLibrary> lib = (__bridge id<MTLLibrary>)ctx.library;
    id<MTLDevice>  dev = (__bridge id<MTLDevice>)ctx.device;

    id<MTLFunction> vfn = [lib newFunctionWithName:[NSString stringWithUTF8String:d.vertex_fn.c_str()]];
    id<MTLFunction> ffn = [lib newFunctionWithName:[NSString stringWithUTF8String:d.fragment_fn.c_str()]];
    if (!vfn) { fprintf(stderr, "missing vertex fn: %s\n", d.vertex_fn.c_str()); std::exit(1); }
    if (!ffn) { fprintf(stderr, "missing fragment fn: %s\n", d.fragment_fn.c_str()); std::exit(1); }

    MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = vfn;
    desc.fragmentFunction = ffn;
    desc.colorAttachments[0].pixelFormat = (MTLPixelFormat)d.color_pixel_format;
    if (d.blending) {
        desc.colorAttachments[0].blendingEnabled = YES;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }

    NSError* err = nil;
    id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:desc error:&err];
    if (!pso) die(("pso compile " + key).c_str(), err);

    void* p = (__bridge_retained void*)pso;
    render_cache_[key] = p;
    return p;
}

void* PipelineCache::compute_pso(const MetalContext& ctx, const std::string& fn) {
    auto it = compute_cache_.find(fn);
    if (it != compute_cache_.end()) return it->second;

    id<MTLLibrary> lib = (__bridge id<MTLLibrary>)ctx.library;
    id<MTLDevice>  dev = (__bridge id<MTLDevice>)ctx.device;
    id<MTLFunction> f = [lib newFunctionWithName:[NSString stringWithUTF8String:fn.c_str()]];
    if (!f) { fprintf(stderr, "missing compute fn: %s\n", fn.c_str()); std::exit(1); }

    NSError* err = nil;
    id<MTLComputePipelineState> pso = [dev newComputePipelineStateWithFunction:f error:&err];
    if (!pso) die(("compute pso " + fn).c_str(), err);
    void* p = (__bridge_retained void*)pso;
    compute_cache_[fn] = p;
    return p;
}

}
