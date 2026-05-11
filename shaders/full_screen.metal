#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut fs_triangle_vs(uint vid [[vertex_id]]) {
    const float2 verts[3] = { float2(-1,-3), float2(-1, 1), float2( 3, 1) };
    VOut o;
    o.pos = float4(verts[vid], 0, 1);
    o.uv  = verts[vid] * 0.5 + 0.5;
    return o;
}

fragment float4 fs_clear_fs(VOut in [[stage_in]]) {
    return float4(in.uv, 0.2, 1.0);
}
