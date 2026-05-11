#include <gtest/gtest.h>
#include "ocean/Spectrum.h"
#include <complex>
#include <cmath>

TEST(Spectrum, PhillipsZeroAtZeroK) {
    EXPECT_NEAR(mo::phillips({0,0}, {1,0}, 12.0f, 1.0f), 0.0f, 1e-6f);
}

TEST(Spectrum, PhillipsPeaksNearWindWavelength) {
    glm::vec2 wd{1.0f, 0.0f};
    float wind = 12.0f, A = 1.0f;
    float L_peak = wind * wind / 9.81f;
    float k_peak = 6.283f / L_peak;
    float p_peak = mo::phillips({k_peak, 0}, wd, wind, A);
    float p_high = mo::phillips({k_peak * 4, 0}, wd, wind, A);
    EXPECT_GT(p_peak, p_high);
}

TEST(Spectrum, H0HasExpectedSize) {
    mo::SpectrumParams p; p.N = 64;
    auto h0 = mo::generate_h0(p);
    EXPECT_EQ(h0.size(), 64u * 64u);
}

TEST(Spectrum, H0Deterministic) {
    mo::SpectrumParams p; p.N = 32;
    auto a = mo::generate_h0(p);
    auto b = mo::generate_h0(p);
    for (size_t i = 0; i < a.size(); ++i) {
        EXPECT_FLOAT_EQ(a[i].x, b[i].x);
        EXPECT_FLOAT_EQ(a[i].y, b[i].y);
    }
}
