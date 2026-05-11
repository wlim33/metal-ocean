#import "render/OceanRenderer.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"
#import "ocean/ProjectedGrid.h"
#import "core/OrbitCamera.h"
#include "shader_types.h"
#import <Metal/Metal.h>
#include <cstring>

namespace mo {

void OceanRenderer::init(const MetalContext& ctx, PipelineCache& cache) {
    MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
    id<MTLLibrary> lib = (__bridge id<MTLLibrary>)ctx.library;
    desc.vertexFunction   = [lib newFunctionWithName:@"ocean_vs"];
    desc.fragmentFunction = [lib newFunctionWithName:@"ocean_wireframe_fs"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

    MTLVertexDescriptor* vd = [MTLVertexDescriptor new];
    vd.attributes[0].format = MTLVertexFormatFloat2;
    vd.attributes[0].offset = 0;
    vd.attributes[0].bufferIndex = 0;
    vd.layouts[0].stride = sizeof(float) * 2;
    vd.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    desc.vertexDescriptor = vd;

    NSError* err = nil;
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:desc error:&err];
    if (!pso) {
        fprintf(stderr, "ocean wireframe pso failed: %s\n", err.localizedDescription.UTF8String);
        std::exit(1);
    }
    pso_wire_ = (__bridge_retained void*)pso;

    for (int i = 0; i < RING; ++i) {
        cam_buf_[i] = make_buffer(ctx, sizeof(CameraUniforms), true);
    }
}

void OceanRenderer::upload_grid(const MetalContext& ctx, const ProjectedGridOutput& g, int idx) {
    size_t v_bytes = g.vertices_xz.size() * sizeof(float) * 2;
    size_t i_bytes = g.indices.size() * sizeof(uint32_t);
    int slot = idx % RING;
    if (vbo_[slot].size < v_bytes) { destroy_buffer(vbo_[slot]); vbo_[slot] = make_buffer(ctx, v_bytes, true); }
    if (ibo_[slot].size < i_bytes) { destroy_buffer(ibo_[slot]); ibo_[slot] = make_buffer(ctx, i_bytes, true); }
    std::memcpy(vbo_[slot].cpu_ptr, g.vertices_xz.data(), v_bytes);
    std::memcpy(ibo_[slot].cpu_ptr, g.indices.data(),    i_bytes);
    index_count_[slot] = g.indices.size();
}

void OceanRenderer::encode_wireframe(void* encoder, const OrbitCamera& cam, int idx) {
    int slot = idx % RING;
    if (!index_count_[slot]) return;
    id<MTLRenderCommandEncoder> enc = (__bridge id<MTLRenderCommandEncoder>)encoder;

    CameraUniforms u;
    auto v = cam.view(); auto p = cam.proj(); auto vp = p * v;
    std::memcpy(&u.view,       &v[0][0],  sizeof(float)*16);
    std::memcpy(&u.proj,       &p[0][0],  sizeof(float)*16);
    std::memcpy(&u.view_proj,  &vp[0][0], sizeof(float)*16);
    u.position = (simd_float3){ cam.position().x, cam.position().y, cam.position().z };
    std::memcpy(cam_buf_[slot].cpu_ptr, &u, sizeof(CameraUniforms));

    [enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso_wire_];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)vbo_[slot].handle offset:0 atIndex:0];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)cam_buf_[slot].handle offset:0 atIndex:1];
    [enc setTriangleFillMode:MTLTriangleFillModeLines];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:index_count_[slot]
                     indexType:MTLIndexTypeUInt32
                   indexBuffer:(__bridge id<MTLBuffer>)ibo_[slot].handle
             indexBufferOffset:0];
}
}
