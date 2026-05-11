#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

// Phillips dispersion: omega = sqrt(g * |k|)
static float omega(float2 k) {
    return sqrt(9.81 * length(k));
}

kernel void spectrum_kernel(
    texture2d<float, access::read>  h0      [[texture(0)]],
    texture2d<float, access::write> htilde  [[texture(1)]],
    constant CascadeUniforms&       U       [[buffer(0)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)U.N || gid.y >= (uint)U.N) return;
    int ic = (int)gid.x - U.N / 2;
    int jc = (int)gid.y - U.N / 2;
    float2 k = float2(6.283185 * ic / U.L, 6.283185 * jc / U.L);
    float  w = omega(k);
    float  cw = cos(w * U.t);
    float  sw = sin(w * U.t);
    float4 h0p = h0.read(gid);
    // h0p.xy = h0(k), h0p.zw = h0(-k)*
    // h(k,t) = h0(k)*exp(iwt) + conj(h0(-k))*exp(-iwt)
    float2 e1 = float2(cw, sw);
    float2 e2 = float2(cw, -sw);
    float2 a  = float2(h0p.x * e1.x - h0p.y * e1.y, h0p.x * e1.y + h0p.y * e1.x);
    float2 b  = float2(h0p.z * e2.x - h0p.w * e2.y, h0p.z * e2.y + h0p.w * e2.x);
    float2 h  = a + b;
    htilde.write(float4(h, 0, 0), gid);
}
