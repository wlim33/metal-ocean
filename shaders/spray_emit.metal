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
    // Emission logic lands in Task 6; compiling signature first.
    (void)particles; (void)counters; (void)U;
}
