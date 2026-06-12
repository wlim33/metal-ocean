#import "ocean/Cascade.h"
#import "ocean/Spectrum.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "shader_types.h"
#import <Metal/Metal.h>
#include <cstring>
#include <vector>

namespace mo {

// Zero mip 0 of a private texture via a shared staging copy. Mip levels are
// regenerated every frame by encode_mipgen, so only level 0 needs clearing.
static void clear_texture(const MetalContext& ctx, Texture& tex, int N) {
    std::vector<uint16_t> zeros((size_t)N * N * 4, 0);  // RGBA16F zero bits
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    MTLTextureDescriptor* sd = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                     width:N height:N mipmapped:NO];
    sd.usage = MTLTextureUsageShaderRead;
    sd.storageMode = MTLStorageModeShared;
    id<MTLTexture> staging = [dev newTextureWithDescriptor:sd];
    [staging replaceRegion:MTLRegionMake2D(0, 0, N, N) mipmapLevel:0
                 withBytes:zeros.data() bytesPerRow:N * sizeof(uint16_t) * 4];
    id<MTLCommandQueue> q = (__bridge id<MTLCommandQueue>)ctx.queue;
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:staging sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(N, N, 1)
                toTexture:(__bridge id<MTLTexture>)tex.handle
         destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
    [cb commit]; [cb waitUntilCompleted];
}

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
    h0_                = make_texture_2d(ctx, N, N, TexFormat::RGBA32F, false, false);
    tilde_             = make_texture_2d(ctx, N, N, TexFormat::RGBA32F, true, false);
    ifft_intermediate_ = make_texture_2d(ctx, N, N, TexFormat::RGBA32F, true, false);
    field_             = make_texture_2d(ctx, N, N, TexFormat::RGBA32F, true, false);
    disp_              = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false);
    // Normals are sampled heavily minified toward the horizon; without mips
    // those fetches thrash the texture cache (~2x fragment cost) and shimmer.
    // Levels are regenerated each frame in encode_mipgen().
    normal_            = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false, true);
    foam_[0] = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false, true);
    foam_[1] = make_texture_2d(ctx, N, N, TexFormat::RGBA16F, true, false, true);
    clear_texture(ctx, foam_[0], N);
    clear_texture(ctx, foam_[1], N);

    uniforms_ = make_buffer(ctx, sizeof(CascadeUniforms), true);

    pso_spectrum_ = cache.compute_pso(ctx, "spectrum_kernel");
    pso_fft_      = cache.compute_pso(ctx, "fft_kernel");
    pso_post_     = cache.compute_pso(ctx, "post_fft_kernel");
    pso_foam_     = cache.compute_pso(ctx, "foam_update_kernel");

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

void Cascade::encode_spectrum(void* compute_encoder, float time, const CascadeParams& p) {
    id<MTLComputeCommandEncoder> enc = (__bridge id<MTLComputeCommandEncoder>)compute_encoder;
    int N = p.N;

    CascadeUniforms u{ N, p.size_m, time, p.choppiness,
                       p.foam_bias, p.foam_gain, p.foam_decay_factor,
                       p.foam_dispersal, p.inv_n };
    std::memcpy(uniforms_.cpu_ptr, &u, sizeof(u));

    // Spectrum: h0 -> h-tilde (.xy) + D̂x+i·D̂z (.zw) in one texture.
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_spectrum_];
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)h0_.handle    atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)tilde_.handle atIndex:1];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
}

void Cascade::encode_fft(void* compute_encoder, const CascadeParams& p) {
    id<MTLComputeCommandEncoder> enc = (__bridge id<MTLComputeCommandEncoder>)compute_encoder;
    int N = p.N;

    // 2D IFFT of the packed field: row pass then column pass.
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_fft_];
    [enc setThreadgroupMemoryLength:(NSUInteger)N * sizeof(float) * 4 atIndex:0];

    FftPassUniforms fu_h{ N, 0 };
    [enc setBytes:&fu_h length:sizeof(fu_h) atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)tilde_.handle             atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)ifft_intermediate_.handle atIndex:1];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(N, 1, 1)];
    FftPassUniforms fu_v{ N, 1 };
    [enc setBytes:&fu_v length:sizeof(fu_v) atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)ifft_intermediate_.handle atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)field_.handle             atIndex:1];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(1, N, 1)];
}

void Cascade::encode_post(void* compute_encoder, const CascadeParams& p) {
    id<MTLComputeCommandEncoder> enc = (__bridge id<MTLComputeCommandEncoder>)compute_encoder;
    int N = p.N;

    // Post-FFT: packed h + Dx/Dz field -> disp + normal
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_post_];
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)field_.handle  atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)disp_.handle   atIndex:1];
    [enc setTexture:(__bridge id<MTLTexture>)normal_.handle atIndex:2];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];

    // Foam accumulation: ping-pong flip happens here, once per frame.
    foam_cur_ ^= 1;
    [enc setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_foam_];
    [enc setBuffer:(__bridge id<MTLBuffer>)uniforms_.handle offset:0 atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)foam_[foam_cur_].handle     atIndex:0];
    [enc setTexture:(__bridge id<MTLTexture>)foam_[foam_cur_ ^ 1].handle atIndex:1];
    [enc setTexture:(__bridge id<MTLTexture>)normal_.handle              atIndex:2];
    [enc dispatchThreads:MTLSizeMake(N, N, 1) threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
}

void Cascade::encode(void* compute_encoder, float time, const CascadeParams& p) {
    encode_spectrum(compute_encoder, time, p);
    encode_fft(compute_encoder, p);
    encode_post(compute_encoder, p);
}

void Cascade::encode_mipgen(void* blit_encoder) {
    id<MTLBlitCommandEncoder> blit = (__bridge id<MTLBlitCommandEncoder>)blit_encoder;
    [blit generateMipmapsForTexture:(__bridge id<MTLTexture>)normal_.handle];
    [blit generateMipmapsForTexture:(__bridge id<MTLTexture>)foam_[foam_cur_].handle];
}

}
