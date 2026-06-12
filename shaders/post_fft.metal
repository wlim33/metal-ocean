#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

// Combines the IFFT'd packed field into the displacement texture and computes
// surface normals + the folding Jacobian for foam. field.x = h (real part
// after the inverse transform), field.zw = (Dx, Dz); each neighbor read feeds
// both the height slope and the displacement Jacobian.
kernel void post_fft_kernel(
    texture2d<float, access::read>  field         [[texture(0)]],
    texture2d<float, access::write> disp_out      [[texture(1)]],
    texture2d<float, access::write> normal_out    [[texture(2)]],
    constant CascadeUniforms&       U             [[buffer(0)]],
    uint2 gid                                    [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)U.N || gid.y >= (uint)U.N) return;
    int N = U.N;
    int sign_ = ((int(gid.x + gid.y)) & 1) == 0 ? 1 : -1; // FFT shift
    // The fft_kernel runs unnormalized inverse DFTs, so the row+column pair
    // accumulates an N² factor relative to a true inverse FFT. Undo that here.
    float inv_n2 = 1.0 / ((float)N * (float)N);
    float4 c = field.read(gid) * (float)sign_ * inv_n2;
    float  h    = c.x;
    float2 dxdz = c.zw * U.choppiness;

    int xm = ((int)gid.x - 1 + N) % N;
    int xp = ((int)gid.x + 1) % N;
    int ym = ((int)gid.y - 1 + N) % N;
    int yp = ((int)gid.y + 1) % N;
    float s_xm = ((xm + (int)gid.y) & 1) == 0 ? 1.0 : -1.0;
    float s_xp = ((xp + (int)gid.y) & 1) == 0 ? 1.0 : -1.0;
    float s_ym = (((int)gid.x + ym) & 1) == 0 ? 1.0 : -1.0;
    float s_yp = (((int)gid.x + yp) & 1) == 0 ? 1.0 : -1.0;
    float4 cxp = field.read(uint2(xp, gid.y)) * s_xp;
    float4 cxm = field.read(uint2(xm, gid.y)) * s_xm;
    float4 cyp = field.read(uint2(gid.x, yp)) * s_yp;
    float4 cym = field.read(uint2(gid.x, ym)) * s_ym;

    // Per-meter derivatives. Central diff spans two texels (Δx = L/N meters),
    // and the raw reads still need the 1/N² inverse-FFT scale:
    //   d/dx = (raw[xp] - raw[xm]) / 2 · (1/N²) · (N/L)
    float slope_scale = 1.0 / ((float)N * U.L);
    float dhdx = (cxp.x - cxm.x) * 0.5 * slope_scale;
    float dhdy = (cyp.x - cym.x) * 0.5 * slope_scale;

    disp_out.write(float4(dxdz.x, h, dxdz.y, 0.0), gid);

    float3 n = normalize(float3(-dhdx, 1.0, -dhdy));

    // Folding Jacobian of the horizontal displacement map (choppiness λ folded
    // into the derivatives, so foam tracks the displacement actually applied):
    //   J = (1 + λ·∂Dx/∂x)(1 + λ·∂Dz/∂z) − (λ·∂Dx/∂z)(λ·∂Dz/∂x)
    // J < ~0 means the surface folds over itself — wave crests breaking.
    float dd = 0.5 * slope_scale * U.choppiness;
    float2 ddx = (cxp.zw - cxm.zw) * dd;
    float2 ddz = (cyp.zw - cym.zw) * dd;
    // ddx = (∂Dx/∂x, ∂Dz/∂x), ddz = (∂Dx/∂z, ∂Dz/∂z)
    float jacobian = (1.0 + ddx.x) * (1.0 + ddz.y) - ddz.x * ddx.y;

    normal_out.write(float4(n, jacobian), gid);
}
