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
    dxdz_tilde_        = make_texture_2d(ctx, N, N, TexFormat::RG32F, true, false);
    dxdz_intermediate_ = make_texture_2d(ctx, N, N, TexFormat::RG32F, true, false);
    dxdz_field_        = make_texture_2d(ctx, N, N, TexFormat::RG32F, true, false);
    disp_              = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false);
    // Normals are sampled heavily minified toward the horizon; without mips
    // those fetches thrash the texture cache (~2x fragment cost) and shimmer.
    // Levels are regenerated each frame in encode_mipgen().
    normal_            = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false, true);

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
    sp.amplitude = p.amplitude;
    sp.swell = p.swell;
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

    // Spectrum: produces htilde (h) and packed dxdz_tilde (D̂x + i·D̂z) from h0.
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)h0_.handle         atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)htilde_.handle     atIndex:1];
    [enc setTexture:(__bridge id<MTLTexture>)dxdz_tilde_.handle atIndex:2];
    dispatch_n2(pso_spectrum_);

    // 2D IFFT for h and for the packed Dx+iDz: row pass then column pass.
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_fft_];
    [enc setThreadgroupMemoryLength:N * sizeof(float) * 2 atIndex:0];

    auto fft_pair = [&](void* in_h, void* mid_h, void* out_h) {
        FftPassUniforms fu_h{ N, 0 };
        [enc setBytes:&fu_h length:sizeof(fu_h) atIndex:0];
        [enc setTexture:(__bridge id<MTLTexture>)in_h  atIndex:0];
        [enc setTexture:(__bridge id<MTLTexture>)mid_h atIndex:1];
        [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(N, 1, 1)];
        FftPassUniforms fu_v{ N, 1 };
        [enc setBytes:&fu_v length:sizeof(fu_v) atIndex:0];
        [enc setTexture:(__bridge id<MTLTexture>)mid_h atIndex:0];
        [enc setTexture:(__bridge id<MTLTexture>)out_h atIndex:1];
        [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(1, N, 1)];
    };
    fft_pair(htilde_.handle,     ifft_intermediate_.handle, height_.handle);
    fft_pair(dxdz_tilde_.handle, dxdz_intermediate_.handle, dxdz_field_.handle);

    // Post-FFT: height + packed Dx/Dz -> disp + normal
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_post_];
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)height_.handle     atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)dxdz_field_.handle atIndex:1];
    [enc setTexture:(__bridge id<MTLTexture>)disp_.handle       atIndex:2];
    [enc setTexture:(__bridge id<MTLTexture>)normal_.handle     atIndex:3];
    dispatch_n2(pso_post_);
}

void Cascade::encode_mipgen(void* blit_encoder) {
    id<MTLBlitCommandEncoder> blit = (__bridge id<MTLBlitCommandEncoder>)blit_encoder;
    [blit generateMipmapsForTexture:(__bridge id<MTLTexture>)normal_.handle];
}

}
