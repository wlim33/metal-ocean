#include <metal_stdlib>
#include "shader_types.h"
#include "spray_common.h"
using namespace metal;

// Particle/counter layouts are duplicated across the spray_*.metal files
// (MSL-only structs, never cross to C++) — keep byte-identical. packed_float3
// is load-bearing: native float3 is 16-byte aligned, which would double the
// struct stride past the 32-byte buffer allocation in SprayRenderer.mm.
struct SprayParticle { packed_float3 pos; float age; packed_float3 vel; float inv_life; };
struct SprayCounters { atomic_uint ring_head; atomic_uint alive; };

kernel void spray_emit_kernel(
    device SprayParticle*  particles [[buffer(0)]],
    device SprayCounters*  counters  [[buffer(1)]],
    constant SprayUniforms& U        [[buffer(2)]],
    array<texture2d<float>, MAX_CASCADES> normal_tex [[texture(0)]],
    array<texture2d<float>, MAX_CASCADES> disp_tex   [[texture(MAX_CASCADES)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= SPRAY_CANDIDATES) return;

    // Stratified candidate in a camera-centered annulus, importance toward
    // the camera: r = inner * (outer/inner)^u  (log distribution).
    float u1 = sprayc_hash01(gid, (uint)U.frame_index * 2654435761u);
    float u2 = sprayc_hash01(gid ^ 0x9E3779B9u, (uint)U.frame_index);
    float r     = U.annulus_inner * pow(U.annulus_outer / U.annulus_inner, u1);
    float theta = 6.2831853 * u2;
    float2 xz   = U.camera_pos.xz + r * float2(cos(theta), sin(theta));

    // Combined folding J at xz (same construction as the shading W path).
    constexpr sampler smp(filter::linear, address::repeat);
    float J = 0.0;
    for (int i = 0; i < U.cascade_count; ++i) {
        float j_own = normal_tex[i].sample(smp, xz / U.cascade_size[i], level(0)).w;
        J += j_own - 1.0 + U.inv_n;
    }

    float p = sprayc_emit_p(J, U.bias, U.gain, U.dt);
    if (sprayc_hash01(gid * 747796405u, (uint)U.frame_index ^ 0x85EBCA6Bu) >= p) return;

    // Spawn at the displaced surface, slightly lifted.
    float3 disp = float3(0.0);
    for (int i = 0; i < U.cascade_count; ++i)
        disp += disp_tex[i].sample(smp, xz / U.cascade_size[i], level(0)).xyz;
    float3 pos = float3(xz.x + disp.x, disp.y + 0.05, xz.y + disp.z);

    // Launch: near-horizontal downwind, small upward kick, lateral jitter.
    float s1 = sprayc_hash01(gid, 0xA511E9B3u ^ (uint)U.frame_index);
    float s2 = sprayc_hash01(gid, 0xC2B2AE35u ^ (uint)U.frame_index);
    float s3 = sprayc_hash01(gid, 0x27D4EB2Fu ^ (uint)U.frame_index);
    float2 wind_n = float2(U.wind_vel.x, U.wind_vel.z)
                  / max(length(float2(U.wind_vel.x, U.wind_vel.z)), 1e-4);
    float2 lateral = float2(-wind_n.y, wind_n.x) * (s2 - 0.5) * 1.2;
    float3 vel = float3(U.wind_vel.x, 0.0, U.wind_vel.z) * (0.7 + 0.4 * s1)
               + float3(lateral.x, 0.3 + 0.6 * s3, lateral.y);

    uint cursor = atomic_fetch_add_explicit(&counters->ring_head, 1u, memory_order_relaxed);
    uint slot   = sprayc_ring_slot(cursor, SPRAY_POOL);
    device SprayParticle& pt = particles[slot];
    pt.pos = packed_float3(pos);
    pt.age = 0.0;
    pt.vel = packed_float3(vel);
    pt.inv_life = 1.0 / (U.lifetime_s * (0.7 + 0.6 * s1));
}
