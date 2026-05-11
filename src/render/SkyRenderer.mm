#import "render/SkyRenderer.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
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
}
