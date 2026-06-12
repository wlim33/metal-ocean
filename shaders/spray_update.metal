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

    // Horizontal axes relax toward the wind (advection); vertical integrates
    // weak gravity with weaker drag (spume floats) — shared-header math.
    // MSL does not permit thread& to bind to vector elements (swizzles are
    // not lvalues in Metal IR), so extract to scalars before calling the
    // shared-header helpers, then write back.
    // design §5: drag=2.0, g_eff=2.5; drag*0.3=0.6 vertical drag coefficient.
    { float vx = vel.x; sprayc_relax(vx, U.wind_vel.x, 2.0, U.dt); vel.x = vx; }
    { float vz = vel.z; sprayc_relax(vz, U.wind_vel.z, 2.0, U.dt); vel.z = vz; }
    {
        float vy = vel.y;
        float vx_dummy = 0.0;
        sprayc_integrate(vx_dummy, vy, 0.0, 2.0, 2.5, U.dt);
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
    float fade_in  = sprayc_saturate(t * 10.0);
    float fade_out = sprayc_saturate((1.0 - t) * 2.5);
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
    args->instanceCount = atomic_load_explicit(&counters->alive, memory_order_relaxed);
    args->indexStart = 0; args->baseVertex = 0; args->baseInstance = 0;
}
