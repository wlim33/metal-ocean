#include <metal_stdlib>
#include "shader_types.h"
#include "foam_common.h"
using namespace metal;

// Persistent whitecap accumulation (design §3.2): folding deposits foam,
// previous foam disperses (tent blur) and decays exponentially. The foam
// value doubles as age: 1 = fresh crest, -> 0 = dissolved. Runs per cascade
// right after post_fft_kernel; reads the standalone Jacobian that
// post_fft_kernel stored in normal.w and re-derives the D&B k-share from it.
kernel void foam_update_kernel(
    texture2d<float, access::write>  foam_out  [[texture(0)]],
    texture2d<float, access::sample> foam_prev [[texture(1)]],
    texture2d<float, access::read>   normal_in [[texture(2)]],
    constant CascadeUniforms&        U         [[buffer(0)]],
    uint2 gid                                  [[thread_position_in_grid]])
{
    if (gid.x >= (uint)U.N || gid.y >= (uint)U.N) return;
    constexpr sampler smp(filter::linear, address::repeat);

    float j_own = normal_in.read(gid).w;
    float k     = j_own - 1.0 + U.inv_n;          // inverse of foamc_j_own

    float deposit = saturate(U.foam_gain * (U.foam_bias - j_own));

    // 3x3 tent blur of last frame's foam at radius foam_dispersal texels.
    // level(0) is load-bearing: only the freshly-written texture gets new
    // mips each frame, so foam_prev's higher mip levels are one frame stale.
    float2 texel = 1.0 / float2(U.N, U.N);
    float2 uv    = (float2(gid) + 0.5) * texel;
    float prev;
    if (U.foam_dispersal > 0.0) {
        const float w[3] = {0.25, 0.5, 0.25};
        prev = 0.0;
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx)
                prev += w[dx + 1] * w[dy + 1] *
                        foam_prev.sample(smp, uv + float2(dx, dy) * U.foam_dispersal * texel,
                                         level(0)).z;
    } else {
        prev = foam_prev.sample(smp, uv, level(0)).z;   // dispersal off: point read
    }

    float foam = max(deposit, prev * U.foam_decay_factor);
    // saturate at write: a NaN/Inf here would persist forever (design §8).
    foam_out.write(float4(k, k * k, saturate(foam), 0.0), gid);
}
