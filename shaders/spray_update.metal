#include <metal_stdlib>
#include "shader_types.h"
#include "spray_common.h"
using namespace metal;

// Keep byte-identical with spray_emit.metal / spray_billboard.metal.
struct SprayParticle { float3 pos; float age; float3 vel; float inv_life; };
struct SprayCounters { atomic_uint ring_head; atomic_uint alive; };
struct SprayInstance { float3 pos; float size; float2 stretch; float alpha; float _pad; };

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
