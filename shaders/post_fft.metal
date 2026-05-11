#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

// Takes 2D-FFT result for heights and produces displacement xyz + normal + jacobian.
// Inputs: height_field (R = re, G = im) for h(x,t). For full Tessendorf we'd also FFT
// slope and choppy displacement; here we approximate slope from finite differences and
// scale horizontal displacement by choppiness.
kernel void post_fft_kernel(
    texture2d<float, access::read>  hfield        [[texture(0)]],
    texture2d<float, access::write> disp_out      [[texture(1)]],
    texture2d<float, access::write> normal_out    [[texture(2)]],
    constant CascadeUniforms&       U             [[buffer(0)]],
    uint2 gid                                    [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)U.N || gid.y >= (uint)U.N) return;
    int N = U.N;
    int sign_ = ((int(gid.x + gid.y)) & 1) == 0 ? 1 : -1; // FFT shift
    float h = hfield.read(gid).x * (float)sign_;

    int xm = ((int)gid.x - 1 + N) % N;
    int xp = ((int)gid.x + 1) % N;
    int ym = ((int)gid.y - 1 + N) % N;
    int yp = ((int)gid.y + 1) % N;
    int s_xm = ((xm + (int)gid.y) & 1) == 0 ? 1 : -1;
    int s_xp = ((xp + (int)gid.y) & 1) == 0 ? 1 : -1;
    int s_ym = (((int)gid.x + ym) & 1) == 0 ? 1 : -1;
    int s_yp = (((int)gid.x + yp) & 1) == 0 ? 1 : -1;
    float dhdx = (hfield.read(uint2(xp, gid.y)).x * s_xp - hfield.read(uint2(xm, gid.y)).x * s_xm) * 0.5;
    float dhdy = (hfield.read(uint2(gid.x, yp)).x * s_yp - hfield.read(uint2(gid.x, ym)).x * s_ym) * 0.5;

    float dx = -dhdx * U.choppiness * (U.L / (float)N);
    float dz = -dhdy * U.choppiness * (U.L / (float)N);

    disp_out.write(float4(dx, h, dz, 0.0), gid);

    float3 n = normalize(float3(-dhdx, 1.0, -dhdy));
    float jacobian = (1.0 + dhdx) * (1.0 + dhdy) - dhdx * dhdy;
    normal_out.write(float4(n, jacobian), gid);
}
