#include <gtest/gtest.h>
#include <cmath>
#include "spray_common.h"

// ---- emission probability ---------------------------------------------------

TEST(SprayMath, EmissionProbabilityShape) {
    const float dt60 = 1.0f / 60.0f;
    // Zero at and above bias.
    EXPECT_FLOAT_EQ(sprayc_emit_p(/*J=*/0.7f, /*bias=*/0.7f, /*gain=*/1.0f, dt60), 0.0f);
    EXPECT_FLOAT_EQ(sprayc_emit_p(0.9f, 0.7f, 1.0f, dt60), 0.0f);
    // Monotonic in the J-deficit.
    EXPECT_GT(sprayc_emit_p(0.3f, 0.7f, 1.0f, dt60),
              sprayc_emit_p(0.5f, 0.7f, 1.0f, dt60));
    // Linear in gain below saturation.
    float p1 = sprayc_emit_p(0.5f, 0.7f, 1.0f, dt60);
    float p2 = sprayc_emit_p(0.5f, 0.7f, 2.0f, dt60);
    EXPECT_NEAR(p2, 2.0f * p1, 1e-6f);
    // Frame-rate independence: p at dt and at dt/2 halves.
    float pa = sprayc_emit_p(0.4f, 0.7f, 1.0f, dt60);
    float pb = sprayc_emit_p(0.4f, 0.7f, 1.0f, dt60 * 0.5f);
    EXPECT_NEAR(pa, 2.0f * pb, 1e-6f);
    // Clamped to [0, 1] even at absurd gain.
    EXPECT_LE(sprayc_emit_p(-2.0f, 0.7f, 8.0f, 1.0f), 1.0f);
    EXPECT_GE(sprayc_emit_p(-2.0f, 0.7f, 8.0f, 1.0f), 0.0f);
}

// ---- integration ------------------------------------------------------------

TEST(SprayMath, VelocityRelaxesTowardWind) {
    float vx = 0.0f, vy = 3.0f;
    const float wind_x = 10.0f;
    for (int i = 0; i < 240; ++i)
        sprayc_integrate(vx, vy, wind_x, /*drag=*/2.0f, /*g_eff=*/2.5f, 1.0f / 60.0f);
    EXPECT_NEAR(vx, wind_x, 0.1f);
    EXPECT_LT(vy, 0.0f);
}

TEST(SprayMath, RelaxConvergesToTarget) {
    float v = 0.0f;
    for (int i = 0; i < 240; ++i) sprayc_relax(v, 10.0f, 2.0f, 1.0f / 60.0f);
    EXPECT_NEAR(v, 10.0f, 0.1f);
}

TEST(SprayMath, SurfaceClampSkims) {
    EXPECT_FLOAT_EQ(sprayc_clamp_to_surface(1.0f, 2.0f, 0.06f), 2.06f);
    EXPECT_FLOAT_EQ(sprayc_clamp_to_surface(3.0f, 2.0f, 0.06f), 3.0f);
}

// ---- ring allocator ----------------------------------------------------------

TEST(SprayMath, RingSlotWraps) {
    const unsigned pool = 65536u;
    EXPECT_EQ(sprayc_ring_slot(0u, pool), 0u);
    EXPECT_EQ(sprayc_ring_slot(65535u, pool), 65535u);
    EXPECT_EQ(sprayc_ring_slot(65536u, pool), 0u);
    EXPECT_EQ(sprayc_ring_slot(65536u * 3u + 7u, pool), 7u);
    // The cursor genuinely crosses uint32 in long sessions (~5 h at 60 fps).
    // Because the pool is a power of two, 2^32 % pool == 0: ring continuity
    // holds straight through the overflow. Pin it.
    unsigned base = 4294967295u;             // UINT32_MAX
    EXPECT_EQ(sprayc_ring_slot(base, pool), 65535u);
    EXPECT_EQ(sprayc_ring_slot(base + 1u, pool), 0u);   // wraps to 0, no gap
    EXPECT_EQ(sprayc_ring_slot(base + 2u, pool), 1u);
}

// ---- hash --------------------------------------------------------------------

TEST(SprayMath, HashDeterministicAndRoughlyUniform) {
    EXPECT_FLOAT_EQ(sprayc_hash01(123u, 456u), sprayc_hash01(123u, 456u));
    EXPECT_NE(sprayc_hash01(123u, 456u), sprayc_hash01(123u, 457u));
    double sum = 0.0;
    for (unsigned i = 0; i < 10000u; ++i) {
        float h = sprayc_hash01(i, 99u);
        EXPECT_GE(h, 0.0f); EXPECT_LT(h, 1.0f);
        sum += h;
    }
    EXPECT_NEAR(sum / 10000.0, 0.5, 0.01);
}
