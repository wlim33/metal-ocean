#import "render/OceanRenderer.h"
#import "render/SkyRenderer.h"
#import "ocean/Cascade.h"
#import "ocean/ProjectedGrid.h"
#import "core/OrbitCamera.h"
#import "core/Config.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "gpu/Texture.h"
#import "shader_types.h"
#import <Metal/Metal.h>
#include <cstring>
#include <cmath>

namespace mo {

void OceanRenderer::init(const MetalContext& ctx, PipelineCache& cache) {
    (void)cache;
    MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
    id<MTLLibrary> lib = (__bridge id<MTLLibrary>)ctx.library;
    desc.vertexFunction   = [lib newFunctionWithName:@"ocean_vs"];
    desc.fragmentFunction = [lib newFunctionWithName:@"ocean_fs"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    MTLVertexDescriptor* vd = [MTLVertexDescriptor new];
    vd.attributes[0].format = MTLVertexFormatFloat2;
    vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0;
    vd.layouts[0].stride = sizeof(float) * 2;
    desc.vertexDescriptor = vd;
    NSError* err = nil;
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:desc error:&err];
    if (!pso) { fprintf(stderr, "ocean pso: %s\n", err.localizedDescription.UTF8String); std::exit(1); }
    pso_ = (__bridge_retained void*)pso;

    for (int i = 0; i < RING; ++i) {
        cam_buf_[i]  = make_buffer(ctx, sizeof(CameraUniforms), true);
        surf_buf_[i] = make_buffer(ctx, sizeof(OceanSurfaceUniforms), true);
    }
}

void OceanRenderer::upload_grid(const MetalContext& ctx, const ProjectedGridOutput& g, int idx) {
    size_t v_bytes = g.vertices_xz.size() * sizeof(float) * 2;
    size_t i_bytes = g.indices.size() * sizeof(uint32_t);
    int slot = idx % RING;
    if (vbo_[slot].size < v_bytes) { destroy_buffer(vbo_[slot]); vbo_[slot] = make_buffer(ctx, v_bytes, true); }
    if (ibo_[slot].size < i_bytes) { destroy_buffer(ibo_[slot]); ibo_[slot] = make_buffer(ctx, i_bytes, true); }
    std::memcpy(vbo_[slot].cpu_ptr, g.vertices_xz.data(), v_bytes);
    // Index content is a pure function of grid topology. indices[1] is the
    // first quad's third corner == cols, so (count, indices[1]) identifies
    // the (cols, rows) pair; skip the ~1.5 MB re-upload when it matches.
    uint32_t key = g.indices.size() > 1 ? g.indices[1] : 0;
    if (index_count_[slot] != g.indices.size() || index_key_[slot] != key) {
        std::memcpy(ibo_[slot].cpu_ptr, g.indices.data(), i_bytes);
        index_key_[slot] = key;
    }
    index_count_[slot] = g.indices.size();
}

void OceanRenderer::encode(void* encoder, const OrbitCamera& cam, const Config& cfg,
                           Cascade* const* cascades, int cascade_count,
                           const SkyRenderer& sky, int frame_index, int debug_view) {
    int slot = frame_index % RING;
    if (!index_count_[slot]) return;
    id<MTLRenderCommandEncoder> enc = (__bridge id<MTLRenderCommandEncoder>)encoder;

    CameraUniforms cu;
    auto v = cam.view(); auto p = cam.proj(); auto vp = p * v;
    std::memcpy(&cu.view, &v[0][0], 64);
    std::memcpy(&cu.proj, &p[0][0], 64);
    std::memcpy(&cu.view_proj, &vp[0][0], 64);
    cu.position = (simd_float3){cam.position().x, cam.position().y, cam.position().z};
    std::memcpy(cam_buf_[slot].cpu_ptr, &cu, sizeof(cu));

    OceanSurfaceUniforms su{};
    su.cascade_count = cascade_count;
    for (int i = 0; i < cascade_count; ++i) {
        su.cascade_size[i] = cfg.cascades[i].size_m;
        su.cascade_normal_weight[i] = cfg.cascades[i].normal_weight;
    }
    float ce = std::cos(cfg.sky.sun_elevation_rad), se = std::sin(cfg.sky.sun_elevation_rad);
    float ca = std::cos(cfg.sky.sun_azimuth_rad),   sa = std::sin(cfg.sky.sun_azimuth_rad);
    su.sun_dir   = (simd_float3){ce * sa, se, ce * ca};
    su.sun_color = (simd_float3){cfg.shading.sun_color.x, cfg.shading.sun_color.y, cfg.shading.sun_color.z};
    su.sun_shininess = cfg.shading.sun_shininess;
    su.deep_water_color = (simd_float3){cfg.shading.deep_water_color.x, cfg.shading.deep_water_color.y, cfg.shading.deep_water_color.z};
    su.depth_fog_density = cfg.shading.depth_fog_density;
    su.extinction_rgb = (simd_float3){cfg.shading.extinction_rgb.x, cfg.shading.extinction_rgb.y, cfg.shading.extinction_rgb.z};
    su.base_thickness_m = cfg.shading.base_thickness_m;
    su.sss_color = (simd_float3){cfg.shading.sss_color.x, cfg.shading.sss_color.y, cfg.shading.sss_color.z};
    su.sss_strength = cfg.shading.sss_strength;
    su.sss_view_boost    = cfg.shading.sss_view_boost;
    su.sss_view_power    = cfg.shading.sss_view_power;
    su.scatter_strength  = cfg.shading.scatter_strength;
    su.foam_bias         = cfg.foam.bias;
    su.foam_albedo       = cfg.foam.albedo;
    su.foam_detail_scale = cfg.foam.detail_scale;
    su.displacement_range_m = cfg.displacement_range_m;
    su.debug_view = debug_view;
    std::memcpy(surf_buf_[slot].cpu_ptr, &su, sizeof(su));

    [enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso_];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)vbo_[slot].handle offset:0 atIndex:0];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)cam_buf_[slot].handle  offset:0 atIndex:1];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)surf_buf_[slot].handle offset:0 atIndex:2];
    [enc setFragmentBuffer:(__bridge id<MTLBuffer>)cam_buf_[slot].handle  offset:0 atIndex:1];
    [enc setFragmentBuffer:(__bridge id<MTLBuffer>)surf_buf_[slot].handle offset:0 atIndex:2];

    for (int i = 0; i < cascade_count; ++i) {
        [enc setVertexTexture:(__bridge id<MTLTexture>)cascades[i]->displacement_handle() atIndex:i];
        [enc setFragmentTexture:(__bridge id<MTLTexture>)cascades[i]->normal_handle() atIndex:i];
        [enc setFragmentTexture:(__bridge id<MTLTexture>)cascades[i]->foam_handle()
                        atIndex:MAX_CASCADES + 1 + i];
    }
    [enc setFragmentTexture:(__bridge id<MTLTexture>)sky.cubemap_handle() atIndex:MAX_CASCADES];
    [enc setFragmentTexture:(__bridge id<MTLTexture>)foam_detail_.handle
                    atIndex:2 * MAX_CASCADES + 1];

    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:index_count_[slot]
                     indexType:MTLIndexTypeUInt32
                   indexBuffer:(__bridge id<MTLBuffer>)ibo_[slot].handle
             indexBufferOffset:0];
}

void OceanRenderer::bake_foam_detail_if_needed(const MetalContext& ctx, void* command_buffer,
                                               PipelineCache& cache) {
    if (foam_detail_baked_) return;
    foam_detail_ = make_texture_2d(ctx, 512, 512, TexFormat::R8Unorm, true, false, true);
    void* pso = cache.compute_pso(ctx, "foam_detail_kernel");
    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)command_buffer;
    id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
    [ce setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso];
    [ce setTexture:(__bridge id<MTLTexture>)foam_detail_.handle atIndex:0];
    [ce dispatchThreads:MTLSizeMake(512, 512, 1) threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
    [ce endEncoding];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit generateMipmapsForTexture:(__bridge id<MTLTexture>)foam_detail_.handle];
    [blit endEncoding];
    foam_detail_baked_ = true;
}
}
