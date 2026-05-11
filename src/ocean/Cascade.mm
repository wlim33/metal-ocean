#import "ocean/Cascade.h"
#import "ocean/Spectrum.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "shader_types.h"
#import <Metal/Metal.h>
#include <cstring>

namespace mo {

static void upload_h0(const MetalContext& ctx, Texture& tex, const std::vector<glm::vec4>& data, int N) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    id<MTLTexture> dst = (__bridge id<MTLTexture>)tex.handle;
    MTLTextureDescriptor* sd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                  width:N height:N mipmapped:NO];
    sd.usage = MTLTextureUsageShaderRead;
    sd.storageMode = MTLStorageModeShared;
    id<MTLTexture> staging = [dev newTextureWithDescriptor:sd];
    [staging replaceRegion:MTLRegionMake2D(0,0,N,N) mipmapLevel:0
                 withBytes:data.data() bytesPerRow:N * sizeof(float) * 4];
    id<MTLCommandQueue> q = (__bridge id<MTLCommandQueue>)ctx.queue;
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:staging sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
              sourceSize:MTLSizeMake(N,N,1) toTexture:dst destinationSlice:0
        destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding];
    [cb commit]; [cb waitUntilCompleted];
}

void Cascade::init(const MetalContext& ctx, PipelineCache& cache, const CascadeParams& p) {
    params_ = p;
    int N = p.N;
    // h0 uses RGBA32F precision; create directly (the generic make_texture_2d uses RGBA16F).
    {
        id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
        MTLTextureDescriptor* d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                      width:N height:N mipmapped:NO];
        d.usage = MTLTextureUsageShaderRead;
        d.storageMode = MTLStorageModePrivate;
        h0_.handle = (__bridge_retained void*)[dev newTextureWithDescriptor:d];
        h0_.width = h0_.height = N; h0_.format = TexFormat::RGBA16F;
    }
    htilde_            = make_texture_2d(ctx, N, N, TexFormat::RG32F, true, false);
    ifft_intermediate_ = make_texture_2d(ctx, N, N, TexFormat::RG32F, true, false);
    height_            = make_texture_2d(ctx, N, N, TexFormat::RG32F, true, false);
    disp_              = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false);
    normal_            = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false);

    uniforms_ = make_buffer(ctx, sizeof(CascadeUniforms), true);

    pso_spectrum_ = cache.compute_pso(ctx, "spectrum_kernel");
    pso_fft_      = cache.compute_pso(ctx, "fft_kernel");
    pso_post_     = cache.compute_pso(ctx, "post_fft_kernel");

    rebuild_h0(ctx, p);
}

void Cascade::rebuild_h0(const MetalContext& ctx, const CascadeParams& p) {
    SpectrumParams sp;
    sp.N = p.N; sp.L = p.size_m;
    sp.wind_speed = p.wind_speed_mps; sp.wind_dir_rad = p.wind_dir_rad;
    sp.seed = p.seed;
    auto data = generate_h0(sp);
    upload_h0(ctx, h0_, data, p.N);
}

void Cascade::encode(void* compute_encoder, float time, const CascadeParams& p) {
    id<MTLComputeCommandEncoder> enc = (__bridge id<MTLComputeCommandEncoder>)compute_encoder;
    int N = p.N;

    CascadeUniforms u{ N, p.size_m, time, p.choppiness };
    std::memcpy(uniforms_.cpu_ptr, &u, sizeof(u));

    auto dispatch_n2 = [&](void* pso) {
        [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso];
        MTLSize tg = MTLSizeMake(16, 16, 1);
        MTLSize grid = MTLSizeMake(N, N, 1);
        [enc dispatchThreads:grid threadsPerThreadgroup:tg];
    };

    // Spectrum
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)h0_.handle    atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)htilde_.handle atIndex:1];
    dispatch_n2(pso_spectrum_);

    // FFT horizontal: htilde -> ifft_intermediate
    FftPassUniforms fu{ N, 0 };
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_fft_];
    [enc setBytes:&fu length:sizeof(fu) atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)htilde_.handle atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)ifft_intermediate_.handle atIndex:1];
    [enc setThreadgroupMemoryLength:N * sizeof(float) * 2 atIndex:0];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(N, 1, 1)];

    // FFT vertical: ifft_intermediate -> height
    fu.direction = 1;
    [enc setBytes:&fu length:sizeof(fu) atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)ifft_intermediate_.handle atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)height_.handle atIndex:1];
    [enc setThreadgroupMemoryLength:N * sizeof(float) * 2 atIndex:0];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(N, 1, 1)];

    // Post-FFT: height -> disp + normal
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_post_];
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)height_.handle atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)disp_.handle   atIndex:1];
    [enc setTexture:(__bridge id<MTLTexture>)normal_.handle atIndex:2];
    dispatch_n2(pso_post_);
}

}
