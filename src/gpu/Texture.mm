#import "gpu/Texture.h"
#import "gpu/MetalContext.h"
#import <Metal/Metal.h>

namespace mo {

static MTLPixelFormat pf(TexFormat f) {
    switch (f) {
        case TexFormat::RG32F:           return MTLPixelFormatRG32Float;
        case TexFormat::RGBA16F:         return MTLPixelFormatRGBA16Float;
        case TexFormat::RGBA32F:         return MTLPixelFormatRGBA32Float;
        case TexFormat::RGBA8Unorm_sRGB: return MTLPixelFormatRGBA8Unorm_sRGB;
        case TexFormat::BGRA8Unorm_sRGB: return MTLPixelFormatBGRA8Unorm_sRGB;
        case TexFormat::R32F:            return MTLPixelFormatR32Float;
    }
}

Texture make_texture_2d(const MetalContext& ctx, uint32_t w, uint32_t h, TexFormat f,
                        bool storage_write, bool render_target, bool mipmapped) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    MTLTextureDescriptor* d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf(f)
                                                                                  width:w height:h
                                                                              mipmapped:(mipmapped ? YES : NO)];
    // generateMipmapsForTexture renders into the mip levels, so mipmapped
    // textures need RenderTarget usage even when never bound as one directly.
    d.usage = MTLTextureUsageShaderRead
            | (storage_write ? MTLTextureUsageShaderWrite : 0)
            | (render_target || mipmapped ? MTLTextureUsageRenderTarget : 0);
    d.storageMode = MTLStorageModePrivate;
    id<MTLTexture> t = [dev newTextureWithDescriptor:d];
    return { (__bridge_retained void*)t, w, h, f };
}

Texture make_texture_cube(const MetalContext& ctx, uint32_t s, TexFormat f) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    MTLTextureDescriptor* d = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:pf(f)
                                                                                    size:s mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    d.storageMode = MTLStorageModePrivate;
    id<MTLTexture> t = [dev newTextureWithDescriptor:d];
    return { (__bridge_retained void*)t, s, s, f };
}

void destroy_texture(Texture& t) {
    if (t.handle) { id<MTLTexture> tt = (__bridge_transfer id<MTLTexture>)t.handle; (void)tt; }
    t = {};
}
}
