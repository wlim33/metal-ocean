#import "render/SkyRenderer.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "gpu/Texture.h"
#import "core/Hash.h"
#import "core/OrbitCamera.h"
#import "core/Config.h"
#import "shader_types.h"
#import <Metal/Metal.h>
#include <glm/gtc/matrix_inverse.hpp>
#include <cstring>
#include <cmath>

namespace mo {

void SkyRenderer::init(const MetalContext& ctx, PipelineCache& cache) {
    RenderPSODesc d; d.vertex_fn = "sky_vs"; d.fragment_fn = "sky_fs";
    pso_ = cache.render_pso(ctx, d);

    RenderPSODesc d2; d2.vertex_fn = "sky_cube_vs"; d2.fragment_fn = "sky_cube_fs";
    d2.color_pixel_format = (unsigned)MTLPixelFormatRGBA16Float;
    pso_cube_ = cache.render_pso(ctx, d2);
}

void SkyRenderer::encode_full_screen(void* encoder, const OrbitCamera& cam, const Config& cfg) {
    id<MTLRenderCommandEncoder> enc = (__bridge id<MTLRenderCommandEncoder>)encoder;
    SkyUniforms u;
    glm::mat4 inv = glm::inverse(cam.view_proj());
    std::memcpy(&u.inv_view_proj, &inv[0][0], sizeof(float)*16);
    float ce = std::cos(cfg.sky.sun_elevation_rad), se = std::sin(cfg.sky.sun_elevation_rad);
    float ca = std::cos(cfg.sky.sun_azimuth_rad),   sa = std::sin(cfg.sky.sun_azimuth_rad);
    u.sun_dir = (simd_float3){ ce * sa, se, ce * ca };
    u.turbidity = cfg.sky.turbidity;
    u.camera_pos = (simd_float3){ cam.position().x, cam.position().y, cam.position().z };

    [enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso_];
    [enc setFragmentBytes:&u length:sizeof(SkyUniforms) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
}

void SkyRenderer::create_cubemap(const MetalContext& ctx, int size) {
    if (cubemap_.handle && (int)cubemap_.width == size) return;
    destroy_texture(cubemap_);
    cubemap_ = make_texture_cube(ctx, (uint32_t)size, TexFormat::RGBA16F, true);
}

void SkyRenderer::bake_cubemap_if_dirty(const MetalContext& ctx, void* command_buffer, const Config& cfg) {
    uint64_t h = fnv1a64(&cfg.sky, sizeof(SkyConfig));
    if (h == last_config_hash_ && cubemap_.handle) return;
    create_cubemap(ctx, cfg.sky.cubemap_resolution);

    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)command_buffer;
    id<MTLTexture> cube = (__bridge id<MTLTexture>)cubemap_.handle;

    // Face basis: +X, -X, +Y, -Y, +Z, -Z
    const simd_float3 forwards[6] = {
        { 1, 0, 0}, {-1, 0, 0}, { 0, 1, 0}, { 0,-1, 0}, { 0, 0, 1}, { 0, 0,-1}
    };
    const simd_float3 ups[6] = {
        { 0, 1, 0}, { 0, 1, 0}, { 0, 0,-1}, { 0, 0, 1}, { 0, 1, 0}, { 0, 1, 0}
    };

    float ce = std::cos(cfg.sky.sun_elevation_rad), se = std::sin(cfg.sky.sun_elevation_rad);
    float ca = std::cos(cfg.sky.sun_azimuth_rad),   sa = std::sin(cfg.sky.sun_azimuth_rad);
    simd_float3 sun = { ce * sa, se, ce * ca };

    for (int face = 0; face < 6; ++face) {
        MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = cube;
        rp.colorAttachments[0].slice = face;
        rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso_cube_];

        struct U { simd_float3 right; float p0; simd_float3 up; float p1;
                   simd_float3 forward; float p2; simd_float3 sun_dir; float turbidity; } u;
        u.forward = forwards[face]; u.up = ups[face];
        u.right = simd_cross(u.forward, u.up);
        u.sun_dir = sun; u.turbidity = cfg.sky.turbidity;
        u.p0 = u.p1 = u.p2 = 0.0f;
        [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
    }

    // Mip chain feeds the foam ambient term (level ~3 of a 128 cube is a
    // cheap directional irradiance proxy). Bake-time only.
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit generateMipmapsForTexture:(__bridge id<MTLTexture>)cubemap_.handle];
    [blit endEncoding];

    last_config_hash_ = h;
}

}
