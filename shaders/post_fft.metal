#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

// Combines the IFFT'd height + packed Dx/Dz fields into the displacement
// texture and computes surface normals + the folding Jacobian for foam.
// dxdz_field holds Dx in .x and Dz in .y (one complex IFFT of D̂x + i·D̂z).
kernel void post_fft_kernel(
    texture2d<float, access::read>  hfield        [[texture(0)]],
    texture2d<float, access::read>  dxdz_field    [[texture(1)]],
    texture2d<float, access::write> disp_out      [[texture(2)]],
    texture2d<float, access::write> normal_out    [[texture(3)]],
    constant CascadeUniforms&       U             [[buffer(0)]],
    uint2 gid                                    [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)U.N || gid.y >= (uint)U.N) return;
    int N = U.N;
    int sign_ = ((int(gid.x + gid.y)) & 1) == 0 ? 1 : -1; // FFT shift
    // The fft_kernel runs unnormalized inverse DFTs, so the row+column pair
    // accumulates an N² factor relative to a true inverse FFT. Undo that here.
    float inv_n2 = 1.0 / ((float)N * (float)N);
    float  h    = hfield.read(gid).x * (float)sign_ * inv_n2;
    float2 dxdz = dxdz_field.read(gid).xy * (float)sign_ * inv_n2 * U.choppiness;

    int xm = ((int)gid.x - 1 + N) % N;
    int xp = ((int)gid.x + 1) % N;
    int ym = ((int)gid.y - 1 + N) % N;
    int yp = ((int)gid.y + 1) % N;
    float s_xm = ((xm + (int)gid.y) & 1) == 0 ? 1.0 : -1.0;
    float s_xp = ((xp + (int)gid.y) & 1) == 0 ? 1.0 : -1.0;
    float s_ym = (((int)gid.x + ym) & 1) == 0 ? 1.0 : -1.0;
    float s_yp = (((int)gid.x + yp) & 1) == 0 ? 1.0 : -1.0;
    // Per-meter derivatives. Central diff spans two texels (Δx = L/N meters),
    // and the raw reads still need the 1/N² inverse-FFT scale:
    //   d/dx = (raw[xp] - raw[xm]) / 2 · (1/N²) · (N/L)
    float slope_scale = 1.0 / ((float)N * U.L);
    float dhdx = (hfield.read(uint2(xp, gid.y)).x * s_xp - hfield.read(uint2(xm, gid.y)).x * s_xm) * 0.5 * slope_scale;
    float dhdy = (hfield.read(uint2(gid.x, yp)).x * s_yp - hfield.read(uint2(gid.x, ym)).x * s_ym) * 0.5 * slope_scale;

    disp_out.write(float4(dxdz.x, h, dxdz.y, 0.0), gid);

    float3 n = normalize(float3(-dhdx, 1.0, -dhdy));

    // Folding Jacobian of the horizontal displacement map (choppiness λ folded
    // into the derivatives, so foam tracks the displacement actually applied):
    //   J = (1 + λ·∂Dx/∂x)(1 + λ·∂Dz/∂z) − (λ·∂Dx/∂z)(λ·∂Dz/∂x)
    // J < ~0 means the surface folds over itself — wave crests breaking.
    float dd = 0.5 * slope_scale * U.choppiness;
    float2 ddx = (dxdz_field.read(uint2(xp, gid.y)).xy * s_xp - dxdz_field.read(uint2(xm, gid.y)).xy * s_xm) * dd;
    float2 ddz = (dxdz_field.read(uint2(gid.x, yp)).xy * s_yp - dxdz_field.read(uint2(gid.x, ym)).xy * s_ym) * dd;
    // ddx = (∂Dx/∂x, ∂Dz/∂x), ddz = (∂Dx/∂z, ∂Dz/∂z)
    float jacobian = (1.0 + ddx.x) * (1.0 + ddz.y) - ddz.x * ddx.y;

    normal_out.write(float4(n, jacobian), gid);
}
