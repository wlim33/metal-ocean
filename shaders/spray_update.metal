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
struct SprayInstance { packed_float3 pos; float size; float2 stretch; float alpha; float _pad; };

kernel void spray_update_kernel(
    device SprayParticle*  particles [[buffer(0)]],
    device SprayCounters*  counters  [[buffer(1)]],
    constant SprayUniforms& U        [[buffer(2)]],
    device SprayInstance*  instances [[buffer(3)]],
    array<texture2d<float>, MAX_CASCADES> disp_tex [[texture(0)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= SPRAY_POOL) return;

    SprayParticle pt = particles[gid];
    if (pt.inv_life <= 0.0 || pt.age * pt.inv_life >= 1.0) return;   // dead slot

    float3 vel = float3(pt.vel);
    float3 pos = float3(pt.pos);

    // Per-particle motion variation (U.turbulence): without it every particle
    // relaxes to the same wind target with the same drag, and the flow reads
    // as a uniform sheet. Factors hash on the SLOT so they are stable for a
    // particle's whole life and deterministic for the bench.
    float tb     = U.turbulence;
    float wind_f = 1.0 + tb * (sprayc_hash01(gid, 7u)  - 0.5);        // 1 +- 0.5*tb
    float drag_f = 1.0 + tb * 1.2 * (sprayc_hash01(gid, 13u) - 0.5);  // 1 +- 0.6*tb
    float g_f    = 1.0 + tb * 0.8 * (sprayc_hash01(gid, 31u) - 0.5);  // 1 +- 0.4*tb
    // Slow lateral weave around the mean flow, proportional to wind speed.
    float2 wn   = float2(U.wind_vel.x, U.wind_vel.z);
    float  wlen = max(length(wn), 1e-4);
    wn /= wlen;
    float2 wperp = float2(-wn.y, wn.x);
    // Quasi-periodic weave: two sines at incommensurate per-particle
    // frequencies never visibly repeat (a single sine reads as a metronome).
    float  ph1 = 6.2831853 * sprayc_hash01(gid, 21u);
    float  ph2 = 6.2831853 * sprayc_hash01(gid, 23u);
    float  fr1 = 6.2831853 * (0.4 + 0.8 * sprayc_hash01(gid, 22u));   // 0.4-1.2 Hz
    float  fr2 = fr1 * (1.618 + 0.6 * sprayc_hash01(gid, 24u));       // golden-ish ratio
    // Amplitudes: 0.55 keeps the second sine subordinate (beat, not chord);
    // 0.28*wlen keeps peak weave ~0.4x wind speed at full turbulence.
    float  osc = (sin(pt.age * fr1 + ph1) + 0.55 * sin(pt.age * fr2 + ph2))
               * tb * 0.28 * wlen;
    float  target_x = U.wind_vel.x * wind_f + wperp.x * osc;
    float  target_z = U.wind_vel.z * wind_f + wperp.y * osc;

    // Horizontal axes relax toward the per-particle wind target (advection);
    // vertical integrates weak gravity with weaker drag - shared-header math.
    {
        float vx = vel.x; sprayc_relax(vx, target_x, 2.0 * drag_f, U.dt); vel.x = vx;
        float vz = vel.z; sprayc_relax(vz, target_z, 2.0 * drag_f, U.dt); vel.z = vz;
        float vy = vel.y;
        float vx_dummy = 0.0;
        sprayc_integrate(vx_dummy, vy, 0.0, 2.0 * drag_f, 2.5 * g_f, U.dt);
        vel.y = vy;
    }
    pos += vel * U.dt;

    // Skim the displaced surface (approximation: sample at current xz).
    constexpr sampler smp(filter::linear, address::repeat);
    float surface_y = 0.0;
    for (int i = 0; i < U.cascade_count; ++i)
        surface_y += disp_tex[i].sample(smp, pos.xz / U.cascade_size[i], level(0)).y;
    pos.y = sprayc_clamp_to_surface(pos.y, surface_y, 0.06);

    pt.age += U.dt;
    pt.pos = packed_float3(pos);
    pt.vel = packed_float3(vel);
    particles[gid] = pt;

    float t = pt.age * pt.inv_life;
    if (t >= 1.0) return;
    float fade_in  = sprayc_saturate(t * 10.0);         // ramp in over first 10% of life
    float fade_out = sprayc_saturate((1.0 - t) * 2.5);   // fade out over the last 40%
    uint idx = atomic_fetch_add_explicit(&counters->alive, 1u, memory_order_relaxed);
    if (idx >= SPRAY_POOL) return;
    device SprayInstance& inst = instances[idx];
    inst.pos = pt.pos;
    inst.size = U.size_m * (0.3 + 0.7 * t);
    inst.stretch = vel.xz;
    inst.alpha = U.alpha * fade_in * fade_out;
    inst._pad = 0.0;
}

kernel void spray_finalize_kernel(
    device SprayCounters*  counters [[buffer(1)]],
    device MTLDrawIndexedPrimitivesIndirectArguments* args [[buffer(4)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid != 0) return;
    args->indexCount = 6;
    // alive <= SPRAY_POOL by construction (update appends <= 1/thread): no clamp needed.
    args->instanceCount = atomic_load_explicit(&counters->alive, memory_order_relaxed);
    args->indexStart = 0; args->baseVertex = 0; args->baseInstance = 0;
}
