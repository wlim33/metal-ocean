#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

// Phillips dispersion: omega = sqrt(g * |k|)
static float omega(float2 k) {
    return sqrt(9.81 * length(k));
}

kernel void spectrum_kernel(
    texture2d<float, access::read>  h0      [[texture(0)]],
    texture2d<float, access::write> tilde   [[texture(1)]],
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
    // h0p.xy = h0(k), h0p.zw = h0(-k)* (conjugate of the mirrored bin, see
    // generate_h0). h(k,t) = h0(k)·exp(iwt) + h0*(-k)·exp(-iwt) is Hermitian,
    // so the IFFT'd height field is real.
    float2 e1 = float2(cw, sw);
    float2 e2 = float2(cw, -sw);
    float2 a  = float2(h0p.x * e1.x - h0p.y * e1.y, h0p.x * e1.y + h0p.y * e1.x);
    float2 b  = float2(h0p.z * e2.x - h0p.w * e2.y, h0p.z * e2.y + h0p.w * e2.x);
    float2 h  = a + b;

    // Packed Tessendorf horizontal displacement:
    //   D̂x + i·D̂z = -i·ĥ·(kx + i·kz)/|k|
    // One complex IFFT then yields Dx in the real part and Dz in the imaginary
    // part (both fields are real because their spectra are Hermitian). Zeroed
    // at DC and at the unpaired Nyquist bins (gid == 0 row/col) where -i·k̂·ĥ
    // would break that symmetry — mirrors displacement_spectrum_from_height,
    // which is validated against the CPU FFT reference in spectrum_test.cpp.
    float kmag = length(k);
    float2 dxdz = float2(0, 0);
    if (kmag > 1e-6 && gid.x != 0 && gid.y != 0) {
        float2 mih = float2(h.y, -h.x);  // -i·ĥ
        float2 q   = k / kmag;
        dxdz = float2(mih.x * q.x - mih.y * q.y, mih.x * q.y + mih.y * q.x);
    }
    // h-tilde in .xy, Dx+i*Dz in .zw: one fft_kernel chain transforms both.
    tilde.write(float4(h, dxdz), gid);
}
