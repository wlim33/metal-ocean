#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

// Keep byte-identical with spray_update.metal. packed_float3 is load-bearing:
// native float3 is 16-byte aligned, which would break the 32-byte stride.
struct SprayInstance { packed_float3 pos; float size; float2 stretch; float alpha; float _pad; };

struct SprayVOut {
    float4 pos [[position]];
    float2 corner;
    float  alpha;
};

vertex SprayVOut spray_vs(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    const device SprayInstance* instances [[buffer(0)]],
    constant CameraUniforms&    cam       [[buffer(1)]])
{
    SprayInstance inst = instances[iid];
    // Quad corners (-1,-1)(1,-1)(-1,1)(1,1) from vid bit pattern.
    float2 c = float2((vid & 1u) ? 1.0 : -1.0, (vid & 2u) ? 1.0 : -1.0);

    // Camera-facing quad in view space, stretched along the screen-projected
    // velocity: fast spume draws as streaks, slow spume as puffs.
    float4 center_v = cam.view * float4(float3(inst.pos), 1.0);
    float3 vel_w = float3(inst.stretch.x, 0.0, inst.stretch.y);
    float3 vel_v = (cam.view * float4(vel_w, 0.0)).xyz;
    float2 dir = vel_v.xy;
    float  speed = length(dir);
    dir = speed > 1e-3 ? dir / speed : float2(1.0, 0.0);
    float2 perp = float2(-dir.y, dir.x);
    float stretch_amt = 1.0 + min(speed * 0.35, 3.0);

    float2 offset = (c.x * dir * stretch_amt + c.y * perp) * inst.size * 0.5;
    center_v.xy += offset;

    SprayVOut o;
    o.pos = cam.proj * center_v;
    o.corner = c;
    o.alpha = inst.alpha;
    return o;
}

fragment float4 spray_fs(SprayVOut in [[stage_in]])
{
    // Procedural radial falloff. Straight (non-premultiplied) alpha — the
    // pipeline blends SourceAlpha / OneMinusSourceAlpha.
    float r2 = dot(in.corner, in.corner);
    float a = in.alpha * saturate(1.0 - r2);
    return float4(float3(0.9, 0.95, 1.0), a);
}
