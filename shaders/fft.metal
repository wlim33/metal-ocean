#include <metal_stdlib>
#include "shader_types.h"
#include "fft_common.h"
using namespace metal;

// One threadgroup per row (direction=0) or column (direction=1). N must be a
// power of two. In-place unnormalized inverse FFT on threadgroup memory; the
// butterfly schedule lives in fft_common.h so the CPU parity test runs the
// exact same arithmetic (see tests/fft_parity_test.cpp).
//
// Each texel carries two independent complex fields — h-tilde in .xy and
// Dx+i*Dz in .zw — so one dispatch transforms both, sharing each butterfly's
// twiddle factor between them.
kernel void fft_kernel(
    texture2d<float, access::read>  in_tex  [[texture(0)]],
    texture2d<float, access::write> out_tex [[texture(1)]],
    constant FftPassUniforms&       U       [[buffer(0)]],
    threadgroup float4*             tg      [[threadgroup(0)]],
    uint2 gid                              [[thread_position_in_grid]],
    uint2 tid                              [[thread_position_in_threadgroup]]
) {
    uint N = (uint)U.N;
    uint bits = fftc_log2(N);
    // Direction=0: each threadgroup is one row (threadgroup size N×1, threads vary in x).
    // Direction=1: each threadgroup is one column (threadgroup size 1×N, threads vary in y).
    uint line  = (U.direction == 0) ? gid.y : gid.x;
    uint local = (U.direction == 0) ? tid.x : tid.y;
    if (line >= N || local >= N) return;
    uint2 src = (U.direction == 0) ? uint2(local, line) : uint2(line, local);
    tg[fftc_bit_reverse(local, bits)] = in_tex.read(src);
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint s = 1; s <= bits; ++s) {
        if (local < N / 2) {
            FftcButterfly bf = fftc_schedule(local, s);
            float2 w = float2(cos(bf.angle), sin(bf.angle));
            float4 a = tg[bf.a];
            float4 b = tg[bf.b];
            float4 t = float4(w.x * b.x - w.y * b.y, w.x * b.y + w.y * b.x,
                              w.x * b.z - w.y * b.w, w.x * b.w + w.y * b.z);
            tg[bf.a] = a + t;
            tg[bf.b] = a - t;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    uint2 dst = (U.direction == 0) ? uint2(local, line) : uint2(line, local);
    out_tex.write(tg[local], dst);
}
