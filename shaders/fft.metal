#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

static uint bit_reverse(uint x, uint bits) {
    uint y = 0;
    for (uint i = 0; i < bits; ++i) { y = (y << 1) | (x & 1u); x >>= 1u; }
    return y;
}

static uint log2u(uint n) {
    uint r = 0; while ((1u << r) < n) ++r; return r;
}

// One thread per row (direction=0) or column (direction=1). N must be a power of two.
// In-place FFT on threadgroup memory.
kernel void fft_kernel(
    texture2d<float, access::read>  in_tex  [[texture(0)]],
    texture2d<float, access::write> out_tex [[texture(1)]],
    constant FftPassUniforms&       U       [[buffer(0)]],
    threadgroup float2*             tg      [[threadgroup(0)]],
    uint2 gid                              [[thread_position_in_grid]],
    uint2 tid                              [[thread_position_in_threadgroup]]
) {
    uint N = (uint)U.N;
    uint bits = log2u(N);
    // Choose row/col index
    uint line = (U.direction == 0) ? gid.y : gid.x;
    if (line >= N) return;

    // Load line into threadgroup memory (bit-reversed)
    uint local = tid.x;
    if (local >= N) return;
    uint2 src = (U.direction == 0) ? uint2(local, line) : uint2(line, local);
    float2 v = in_tex.read(src).xy;
    tg[bit_reverse(local, bits)] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint s = 1; s <= bits; ++s) {
        uint m = 1u << s;
        uint half_m = m >> 1u;
        uint k = local & (half_m - 1u);
        uint group_start = (local / m) * m;
        uint idx_a = group_start + k;
        uint idx_b = idx_a + half_m;
        if (local < N / 2 && idx_b < N) {
            float angle = -6.283185 * (float)k / (float)m;
            float2 w = float2(cos(angle), sin(angle));
            float2 a = tg[idx_a];
            float2 b = tg[idx_b];
            float2 t = float2(w.x * b.x - w.y * b.y, w.x * b.y + w.y * b.x);
            tg[idx_a] = a + t;
            tg[idx_b] = a - t;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    uint2 dst = (U.direction == 0) ? uint2(local, line) : uint2(line, local);
    out_tex.write(float4(tg[local], 0, 0), dst);
}
