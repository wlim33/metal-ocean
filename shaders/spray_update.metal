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
    (void)particles; (void)counters; (void)U; (void)instances;
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
