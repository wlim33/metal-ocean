#pragma once
// Spray/spume math shared between GPU kernels (spray_emit.metal,
// spray_update.metal) and CPU tests (tests/spray_test.cpp). Same pattern as
// foam_common.h: tests must stay Metal-free, so the formulas live here where
// a plain C++ translation unit can execute the exact arithmetic the GPU runs.

// -- stdlib dispatch shims: internal, not part of the spray API --
#ifdef __METAL_VERSION__
#define SPRAYC_REF thread float&
inline float sprayc_saturate(float x) { return metal::saturate(x); }
#else
#define SPRAYC_REF float&
#include <algorithm>
inline float sprayc_saturate(float x) { return std::min(1.0f, std::max(0.0f, x)); }
#endif

// Emission probability per candidate per frame (design §4), normalized to a
// 60 Hz reference so emission is a rate, not per-frame. Wind deliberately
// does not enter: gain owns the rate, wind owns launch speed.
inline float sprayc_emit_p(float j_combined, float bias, float gain, float dt) {
    return sprayc_saturate(sprayc_saturate(gain * (bias - j_combined)) * dt * 60.0f);
}

// Relax a single velocity component toward a target (wind advection).
inline void sprayc_relax(SPRAYC_REF v, float target, float drag, float dt) {
    v += (target - v) * sprayc_saturate(drag * dt);
}

// One (downwind, vertical) integration step (design §5): horizontal relaxes
// toward the wind, vertical has weaker drag plus weak gravity — spume
// floats and drifts, it doesn't arc like ballistic droplets.
inline void sprayc_integrate(SPRAYC_REF vx, SPRAYC_REF vy,
                             float wind_v, float drag, float g_eff, float dt) {
    sprayc_relax(vx, wind_v, drag, dt);
    sprayc_relax(vy, 0.0f, drag * 0.3f, dt);
    vy -= g_eff * dt;
}

// Surface skim (design §5): never below the displaced surface + hover.
inline float sprayc_clamp_to_surface(float y, float surface_y, float hover) {
    float floor_y = surface_y + hover;
    return y < floor_y ? floor_y : y;
}

// Ring allocator slot from a monotonically increasing cursor. Pool is a
// power of two, so the modulo compiles to a mask.
inline unsigned sprayc_ring_slot(unsigned cursor, unsigned pool) {
    return cursor % pool;
}

// Deterministic hash -> [0, 1). Keyed on (id, frame) so bench runs replay
// exactly (no Date/random APIs in kernels).
inline float sprayc_hash01(unsigned a, unsigned b) {
    unsigned h = a * 374761393u + b * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= (h >> 16);
    return (float)(h & 0x00FFFFFFu) / 16777216.0f;
}
