#import "render/SprayRenderer.h"
#import "ocean/Cascade.h"
#import "core/OrbitCamera.h"
#import "core/Config.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "shader_types.h"
#import <Metal/Metal.h>
#include <cstring>
#include <cmath>
#include <algorithm>

namespace mo {

void SprayRenderer::init(const MetalContext& ctx, PipelineCache& cache) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;

    // GPU-private pool buffers.
    particles_ = make_buffer(ctx, (size_t)SPRAY_POOL * 32, false);
    counters_  = make_buffer(ctx, 8, false);
    instances_ = make_buffer(ctx, (size_t)SPRAY_POOL * 32, false);
    indirect_  = make_buffer(ctx, sizeof(MTLDrawIndexedPrimitivesIndirectArguments), false);

    // Quad index buffer: two triangles covering one billboard quad (0,1,2, 2,1,3).
    quad_ibo_ = make_buffer(ctx, 6 * sizeof(uint16_t), true);
    uint16_t indices[6] = {0, 1, 2, 2, 1, 3};
    std::memcpy(quad_ibo_.cpu_ptr, indices, sizeof(indices));

    // CPU-writable per-frame uniform rings.
    for (int i = 0; i < RING; ++i) {
        uniforms_[i] = make_buffer(ctx, sizeof(SprayUniforms), true);
        cam_buf_[i]  = make_buffer(ctx, sizeof(CameraUniforms), true);
    }

    // Zero counters_ (ring_head=0, alive=0) via one-off command buffer.
    id<MTLCommandQueue> q = (__bridge id<MTLCommandQueue>)ctx.queue;
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit fillBuffer:(__bridge id<MTLBuffer>)counters_.handle
               range:NSMakeRange(0, 8)
               value:0];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    // Compute PSOs for the three stub kernels.
    pso_emit_     = cache.compute_pso(ctx, "spray_emit_kernel");
    pso_update_   = cache.compute_pso(ctx, "spray_update_kernel");
    pso_finalize_ = cache.compute_pso(ctx, "spray_finalize_kernel");
    RenderPSODesc dd;
    dd.vertex_fn = "spray_vs";
    dd.fragment_fn = "spray_fs";
    dd.depth_pixel_format = (unsigned)MTLPixelFormatDepth32Float;
    dd.blending = true;
    pso_draw_ = cache.render_pso(ctx, dd);

    // Depth-stencil state: test LessEqual, depth write OFF.
    MTLDepthStencilDescriptor* dsd = [MTLDepthStencilDescriptor new];
    dsd.depthCompareFunction = MTLCompareFunctionLessEqual;
    dsd.depthWriteEnabled    = NO;
    id<MTLDepthStencilState> ds = [dev newDepthStencilStateWithDescriptor:dsd];
    if (!ds) { fprintf(stderr, "spray depth-stencil state creation failed\n"); std::exit(1); }
    depth_state_ = (__bridge_retained void*)ds;
}

void SprayRenderer::encode_compute(void* compute_encoder, int frame_index, float dt,
                                   const Config& cfg, const OrbitCamera& cam,
                                   Cascade* const* cascades, int cascade_count) {
    int slot = frame_index % RING;

    // Fill SprayUniforms into the shared ring buffer.
    SprayUniforms u{};
    auto pos = cam.position();
    u.camera_pos = (simd_float3){pos.x, pos.y, pos.z};
    u.dt = std::min(std::max(dt, 0.0f), 0.1f);
    float wr  = cfg.spray.wind_response;
    float ws  = cfg.wave.wind_speed_mps;
    float wd  = cfg.wave.wind_dir_rad;
    u.wind_vel = (simd_float3){std::cos(wd) * ws * wr, 0.0f, std::sin(wd) * ws * wr};
    u.gain         = cfg.spray.gain;
    u.bias         = cfg.spray.bias;
    u.lifetime_s   = cfg.spray.lifetime_s;
    u.size_m       = cfg.spray.size_m;
    u.alpha        = cfg.spray.alpha;
    u.turbulence   = cfg.spray.turbulence;
    u.annulus_inner = 5.0f;
    u.annulus_outer = 150.0f;
    u.frame_index   = frame_index;
    u.cascade_count = cascade_count;
    for (int i = 0; i < cascade_count && i < MAX_CASCADES; ++i)
        u.cascade_size[i] = cfg.cascades[i].size_m;
    u.inv_n = cascade_count > 0 ? 1.0f / (float)cascade_count : 0.0f;
    std::memcpy(uniforms_[slot].cpu_ptr, &u, sizeof(u));

    // If gain is zero, uniforms are filled but no GPU work is issued.
    if (cfg.spray.gain <= 0.0f) return;

    id<MTLComputeCommandEncoder> ce = (__bridge id<MTLComputeCommandEncoder>)compute_encoder;

    // --- Emit dispatch ---
    [ce setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_emit_];
    [ce setBuffer:(__bridge id<MTLBuffer>)particles_.handle    offset:0 atIndex:0];
    [ce setBuffer:(__bridge id<MTLBuffer>)counters_.handle     offset:0 atIndex:1];
    [ce setBuffer:(__bridge id<MTLBuffer>)uniforms_[slot].handle offset:0 atIndex:2];
    // Normal textures at slots 0..cascade_count-1
    for (int i = 0; i < cascade_count; ++i)
        [ce setTexture:(__bridge id<MTLTexture>)cascades[i]->normal_handle() atIndex:(NSUInteger)i];
    // Displacement textures at slots MAX_CASCADES..MAX_CASCADES+cascade_count-1
    for (int i = 0; i < cascade_count; ++i)
        [ce setTexture:(__bridge id<MTLTexture>)cascades[i]->displacement_handle()
               atIndex:(NSUInteger)(MAX_CASCADES + i)];
    [ce dispatchThreads:MTLSizeMake(SPRAY_CANDIDATES, 1, 1)
   threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];

    // --- Update dispatch ---
    [ce setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_update_];
    [ce setBuffer:(__bridge id<MTLBuffer>)particles_.handle      offset:0 atIndex:0];
    [ce setBuffer:(__bridge id<MTLBuffer>)counters_.handle       offset:0 atIndex:1];
    [ce setBuffer:(__bridge id<MTLBuffer>)uniforms_[slot].handle offset:0 atIndex:2];
    [ce setBuffer:(__bridge id<MTLBuffer>)instances_.handle      offset:0 atIndex:3];
    // Update uses displacement textures starting at slot 0
    for (int i = 0; i < cascade_count; ++i)
        [ce setTexture:(__bridge id<MTLTexture>)cascades[i]->displacement_handle()
               atIndex:(NSUInteger)i];
    [ce dispatchThreads:MTLSizeMake(SPRAY_POOL, 1, 1)
   threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];

    // --- Finalize dispatch (1 thread, writes indirect args) ---
    [ce setComputePipelineState:(__bridge id<MTLComputePipelineState>)pso_finalize_];
    [ce setBuffer:(__bridge id<MTLBuffer>)counters_.handle offset:0 atIndex:1];
    [ce setBuffer:(__bridge id<MTLBuffer>)indirect_.handle offset:0 atIndex:4];
    [ce dispatchThreads:MTLSizeMake(1, 1, 1)
   threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
}

void SprayRenderer::encode_draw(void* render_encoder, int frame_index, const OrbitCamera& cam, const Config& cfg) {
    if (cfg.spray.gain <= 0.0f) return;
    id<MTLRenderCommandEncoder> enc = (__bridge id<MTLRenderCommandEncoder>)render_encoder;

    int slot = frame_index % RING;
    CameraUniforms cu;
    auto v = cam.view(); auto p = cam.proj(); auto vp = p * v;
    std::memcpy(&cu.view, &v[0][0], 64);
    std::memcpy(&cu.proj, &p[0][0], 64);
    std::memcpy(&cu.view_proj, &vp[0][0], 64);
    cu.position = (simd_float3){cam.position().x, cam.position().y, cam.position().z};
    std::memcpy(cam_buf_[slot].cpu_ptr, &cu, sizeof(cu));

    [enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso_draw_];
    [enc setDepthStencilState:(__bridge id<MTLDepthStencilState>)depth_state_];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)instances_.handle offset:0 atIndex:0];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)cam_buf_[slot].handle offset:0 atIndex:1];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:(__bridge id<MTLBuffer>)quad_ibo_.handle
             indexBufferOffset:0
                indirectBuffer:(__bridge id<MTLBuffer>)indirect_.handle
          indirectBufferOffset:0];
}

void SprayRenderer::encode_counter_reset(void* blit_encoder) {
    id<MTLBlitCommandEncoder> blit = (__bridge id<MTLBlitCommandEncoder>)blit_encoder;
    // Reset only the alive counter (offset 4, 4 bytes); ring_head at offset 0 persists.
    [blit fillBuffer:(__bridge id<MTLBuffer>)counters_.handle
               range:NSMakeRange(4, 4)
               value:0];
}

} // namespace mo
