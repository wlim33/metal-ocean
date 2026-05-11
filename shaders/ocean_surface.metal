#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

struct OceanVertexIn { float2 xz [[attribute(0)]]; };
struct VOut { float4 pos [[position]]; float3 world_pos; };

vertex VOut ocean_vs(OceanVertexIn vin [[stage_in]],
                     constant CameraUniforms& cam [[buffer(1)]]) {
    VOut o;
    o.world_pos = float3(vin.xz.x, 0.0, vin.xz.y);
    o.pos = cam.view_proj * float4(o.world_pos, 1.0);
    return o;
}

fragment float4 ocean_wireframe_fs(VOut in [[stage_in]]) {
    return float4(0.2, 0.6, 0.8, 1.0);
}
