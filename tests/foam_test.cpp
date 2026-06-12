#include <gtest/gtest.h>
#include <cmath>
#include "foam_common.h"

// ---- erf approximation -----------------------------------------------------

TEST(FoamMath, ErfMatchesStdWithinAdvertisedError) {
    for (float x = -4.0f; x <= 4.0f; x += 0.01f) {
        EXPECT_NEAR(foamc_erf(x), std::erf(x), 1e-6f) << "x=" << x;
    }
}

TEST(FoamMath, ErfIsOdd) {
    for (float x = 0.0f; x <= 4.0f; x += 0.1f) {
        EXPECT_FLOAT_EQ(foamc_erf(-x), -foamc_erf(x));
    }
}

// ---- k-share decomposition (Dupuy & Bruneton 2012, eq. 7) ------------------

// One active cascade among n: the k-shares must sum exactly to the full
// Jacobian (cross-cascade terms are all zero).
TEST(FoamMath, KShareSumsToFullJacobianWhenOneCascadeActive) {
    const int n = 3; const float inv_n = 1.0f / n;
    const float a = 0.4f, b = -0.2f, c = 0.1f;
    float sum_k = foamc_k_term(a, b, c, inv_n)
                + foamc_k_term(0, 0, 0, inv_n)
                + foamc_k_term(0, 0, 0, inv_n);
    float j_full = (1.0f + a) * (1.0f + b) - c * c;
    EXPECT_NEAR(sum_k, j_full, 1e-6f);
}

// Two active cascades: Σk plus the analytically-known cross terms must equal
// the full Jacobian of the summed displacement. Validates the decomposition
// algebra exactly (the renderer drops the cross terms; D&B: zero mean).
TEST(FoamMath, KShareCrossTermsAccountExactly) {
    const int n = 2; const float inv_n = 0.5f;
    const float a1 = 0.3f, b1 = -0.15f, c1 = 0.08f;
    const float a2 = -0.1f, b2 = 0.25f, c2 = -0.05f;
    float sum_k = foamc_k_term(a1, b1, c1, inv_n) + foamc_k_term(a2, b2, c2, inv_n);
    float cross = a1 * b2 + a2 * b1 - 2.0f * c1 * c2;
    float j_full = (1.0f + a1 + a2) * (1.0f + b1 + b2) - (c1 + c2) * (c1 + c2);
    EXPECT_NEAR(sum_k + cross, j_full, 1e-6f);
}

TEST(FoamMath, JOwnRoundTripsThroughK) {
    const float inv_n = 1.0f / 3.0f;
    const float a = 0.2f, b = 0.1f, c = -0.3f;
    float j_own = (1.0f + a) * (1.0f + b) - c * c;
    float k = foamc_k_term(a, b, c, inv_n);
    EXPECT_NEAR(foamc_j_own(k, inv_n), j_own, 1e-6f);
}

// ---- coverage --------------------------------------------------------------

TEST(FoamMath, CoverageIsBoundedAndMonotonic) {
    const float sigma2 = 0.05f;
    float prev = -1.0f;
    for (float eps = -1.0f; eps <= 2.0f; eps += 0.05f) {
        float w = foamc_coverage(eps, 0.8f, sigma2);
        EXPECT_GE(w, 0.0f); EXPECT_LE(w, 1.0f);
        EXPECT_GE(w, prev) << "W must be non-decreasing in eps";
        prev = w;
    }
    // ...and non-increasing in mu.
    EXPECT_GT(foamc_coverage(0.8f, 0.5f, sigma2), foamc_coverage(0.8f, 1.1f, sigma2));
}

TEST(FoamMath, CoverageFallsBackToStepAtZeroVariance) {
    EXPECT_FLOAT_EQ(foamc_coverage(0.8f, 0.5f, 0.0f), 1.0f);  // mu < eps: folded
    EXPECT_FLOAT_EQ(foamc_coverage(0.8f, 1.0f, 0.0f), 0.0f);  // mu > eps: calm
    // Continuity: tiny variance should approach the step values.
    EXPECT_NEAR(foamc_coverage(0.8f, 0.5f, 1e-5f), 1.0f, 1e-3f);
    EXPECT_NEAR(foamc_coverage(0.8f, 1.0f, 1e-5f), 0.0f, 1e-3f);
}

// ---- decay -----------------------------------------------------------------

TEST(FoamMath, DecayReachesHalfAfterTauLn2) {
    const float tau = 4.0f, dt = 0.016f;
    int steps = (int)std::round(tau * std::log(2.0) / dt);
    float foam = 1.0f, df = foamc_decay_factor(dt, tau);
    for (int i = 0; i < steps; ++i) foam *= df;
    EXPECT_NEAR(foam, 0.5f, 0.01f);
}

TEST(FoamMath, DecayClampsDt) {
    // A 5-second hitch decays no more than a 100 ms frame would.
    EXPECT_FLOAT_EQ(foamc_decay_factor(5.0f, 4.0f), foamc_decay_factor(0.1f, 4.0f));
    EXPECT_FLOAT_EQ(foamc_decay_factor(-1.0f, 4.0f), 1.0f);  // negative dt: no decay
}
