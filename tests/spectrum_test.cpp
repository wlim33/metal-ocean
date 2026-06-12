#include <gtest/gtest.h>
#include "ocean/Spectrum.h"
#include "support/cpu_fft_reference.h"
#include <complex>
#include <cmath>
#include <random>
#include <vector>

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

// swell sharpens directional spreading: off-wind waves are suppressed while
// along-wind waves keep their energy, sweeping from a broad wind-sea (0) to
// long-crested swell (1).
TEST(Spectrum, SwellNarrowsDirectionalSpreading) {
    glm::vec2 wd{1.0f, 0.0f};
    float wind = 12.0f, A = 1.0f;
    glm::vec2 k_diag  = glm::normalize(glm::vec2(1.0f, 1.0f)) * 0.5f; // 45° off wind
    glm::vec2 k_along{0.5f, 0.0f};

    float off_calm    = mo::phillips(k_diag,  wd, wind, A, 0.0f);
    float off_swell   = mo::phillips(k_diag,  wd, wind, A, 1.0f);
    float along_calm  = mo::phillips(k_along, wd, wind, A, 0.0f);
    float along_swell = mo::phillips(k_along, wd, wind, A, 1.0f);

    EXPECT_LT(off_swell, off_calm * 0.5f);     // off-axis strongly suppressed
    EXPECT_FLOAT_EQ(along_swell, along_calm);  // along-wind unchanged
    EXPECT_GT(off_calm, 0.0f);
    // swell = 0 must reproduce the legacy 4-arg behavior.
    EXPECT_FLOAT_EQ(mo::phillips(k_diag, wd, wind, A), off_calm);
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

// Tessendorf: h̃(k,t) = h0(k)e^{iωt} + h0*(-k)e^{-iωt}. The .zw half of each
// texel must be the conjugate of the *mirrored bin's* h0, not an independent
// draw — otherwise h̃ is not Hermitian, the IFFT'd field is complex, and the
// pipeline silently discards the imaginary half of the wave energy.
TEST(Spectrum, H0StoresConjugateOfMirroredBin) {
    mo::SpectrumParams p;
    p.N = 16; p.L = 50.0f; p.amplitude = 1.0f;
    auto d = mo::generate_h0(p);
    int N = p.N;
    for (int j = 0; j < N; ++j) {
        for (int i = 0; i < N; ++i) {
            int im = (N - i) % N;  // bin holding -k in the centered layout
            int jm = (N - j) % N;
            const glm::vec4& v = d[(size_t)j * N + i];
            const glm::vec4& m = d[(size_t)jm * N + im];
            EXPECT_FLOAT_EQ(v.z,  m.x) << "bin (" << i << "," << j << ")";
            EXPECT_FLOAT_EQ(v.w, -m.y) << "bin (" << i << "," << j << ")";
        }
    }
}

TEST(Spectrum, DisplacementSpectrumAppliesTessendorfFormula) {
    int N = 16;
    float L = 4.0f * static_cast<float>(M_PI);
    std::vector<glm::vec2> h(N * N, glm::vec2(0.0f));

    int gxA = N/2 + 3, gyA = N/2 + 1;
    glm::vec2 hA(1.0f, 0.5f);
    h[gyA * N + gxA] = hA;
    int gxB = N/2 - 2, gyB = N/2 + 4;
    glm::vec2 hB(-0.7f, 0.3f);
    h[gyB * N + gxB] = hB;

    std::vector<glm::vec2> dx, dz;
    mo::displacement_spectrum_from_height(h, N, L, dx, dz);

    auto check = [&](int gx, int gy, glm::vec2 hk) {
        int ic = gx - N/2;
        int jc = gy - N/2;
        float kx = 2.0f * static_cast<float>(M_PI) * ic / L;
        float kz = 2.0f * static_cast<float>(M_PI) * jc / L;
        float kmag = std::sqrt(kx*kx + kz*kz);
        glm::vec2 plus_i_h{-hk.y, hk.x}; // +i * (a + ib) = -b + ia
        glm::vec2 expected_dx = (kx / kmag) * plus_i_h;
        glm::vec2 expected_dz = (kz / kmag) * plus_i_h;
        EXPECT_NEAR(dx[gy * N + gx].x, expected_dx.x, 1e-5f);
        EXPECT_NEAR(dx[gy * N + gx].y, expected_dx.y, 1e-5f);
        EXPECT_NEAR(dz[gy * N + gx].x, expected_dz.x, 1e-5f);
        EXPECT_NEAR(dz[gy * N + gx].y, expected_dz.y, 1e-5f);
    };
    check(gxA, gyA, hA);
    check(gxB, gyB, hB);

    // DC bin must be zeroed (avoid 1/0 blow-up).
    EXPECT_FLOAT_EQ(dx[(N/2) * N + (N/2)].x, 0.0f);
    EXPECT_FLOAT_EQ(dx[(N/2) * N + (N/2)].y, 0.0f);
    EXPECT_FLOAT_EQ(dz[(N/2) * N + (N/2)].x, 0.0f);
    EXPECT_FLOAT_EQ(dz[(N/2) * N + (N/2)].y, 0.0f);

    // Untouched bins stay zero.
    EXPECT_FLOAT_EQ(dx[0].x, 0.0f);
    EXPECT_FLOAT_EQ(dx[0].y, 0.0f);
}

// Design proof for the GPU packing in spectrum.metal: because Dx and Dz are
// real fields (Hermitian spectra), a single complex IFFT of D̂x + i·D̂z yields
// Dx in the real part and Dz in the imaginary part — two transforms for the
// price of one. Verified against the CPU FFT reference.
TEST(Spectrum, PackedDxDzIfftUnpacksToBothRealFields) {
    using mo::fft_ref::c64;
    int N = 16;
    float L = 40.0f;
    std::mt19937 rng(99);
    std::uniform_real_distribution<float> ud(-1.0f, 1.0f);

    // Random Hermitian height spectrum in the centered layout.
    std::vector<glm::vec2> h(N * N, glm::vec2(0.0f));
    for (int j = 0; j < N; ++j) {
        for (int i = 0; i < N; ++i) {
            if (i == N/2 && j == N/2) continue;          // DC stays zero
            int im = (N - i) % N, jm = (N - j) % N;
            if (j > jm || (j == jm && i > im)) continue; // fill each pair once
            glm::vec2 v{ud(rng), ud(rng)};
            if (im == i && jm == j) v.y = 0.0f;          // self-paired bins real
            h[(size_t)j * N + i]   = v;
            h[(size_t)jm * N + im] = {v.x, -v.y};
        }
    }
    std::vector<glm::vec2> dx, dz;
    mo::displacement_spectrum_from_height(h, N, L, dx, dz);

    // Centered layout -> standard DFT order (DC at bin 0), as complex arrays.
    auto to_std = [&](auto get) {
        std::vector<c64> out(N * N);
        for (int j = 0; j < N; ++j)
            for (int i = 0; i < N; ++i)
                out[((j + N/2) % N) * N + ((i + N/2) % N)] = get((size_t)j * N + i);
        return out;
    };
    auto dx_std = to_std([&](size_t m) { return c64(dx[m].x, dx[m].y); });
    auto dz_std = to_std([&](size_t m) { return c64(dz[m].x, dz[m].y); });
    auto packed = to_std([&](size_t m) {
        return c64(dx[m].x, dx[m].y) + c64(0, 1) * c64(dz[m].x, dz[m].y);
    });

    mo::fft_ref::fft_2d(dx_std, N, true);
    mo::fft_ref::fft_2d(dz_std, N, true);
    mo::fft_ref::fft_2d(packed, N, true);

    for (int m = 0; m < N * N; ++m) {
        // Hermitian spectra must transform to real fields...
        ASSERT_NEAR(dx_std[m].imag(), 0.0, 1e-6);
        ASSERT_NEAR(dz_std[m].imag(), 0.0, 1e-6);
        // ...so the packed IFFT separates exactly into real/imag parts.
        EXPECT_NEAR(packed[m].real(), dx_std[m].real(), 1e-6);
        EXPECT_NEAR(packed[m].imag(), dz_std[m].real(), 1e-6);
    }
}

// Physical pin — this is the test that would have caught the inverted-chop
// bug ("creases look like valleys"). Whatever signs the spectrum, evolution,
// and FFT conventions use, they must COMPOSE so that the horizontal
// displacement converges at wave crests: dDx/dx < 0 at the height maximum
// (and > 0 at the minimum). Then positive choppiness pinches crests sharp
// and the folding Jacobian J = 1 + λ·dDx/dx dips at crests, where foam
// belongs. Convention-independent, unlike the formula test above.
TEST(Spectrum, ChopConvergesAtCrest) {
    using mo::fft_ref::c64;
    int N = 64;
    float L = 64.0f;

    // Single +x traveling mode (kz = 0) plus its Hermitian partner — the
    // t = 0 state of spectrum.metal's evolution (e^{iωt} = 1, h0 real).
    std::vector<glm::vec2> h(N * N, glm::vec2(0.0f));
    h[(size_t)(N/2) * N + (N/2 + 3)] = {1.0f, 0.0f};
    h[(size_t)(N/2) * N + (N/2 - 3)] = {1.0f, 0.0f};

    std::vector<glm::vec2> dx, dz;
    mo::displacement_spectrum_from_height(h, N, L, dx, dz);

    auto to_std = [&](const std::vector<glm::vec2>& v) {
        std::vector<c64> out(N * N);
        for (int j = 0; j < N; ++j)
            for (int i = 0; i < N; ++i)
                out[((j + N/2) % N) * N + ((i + N/2) % N)] =
                    c64(v[(size_t)j * N + i].x, v[(size_t)j * N + i].y);
        return out;
    };
    auto h_std  = to_std(h);
    auto dx_std = to_std(dx);
    mo::fft_ref::fft_2d(h_std,  N, true);
    mo::fft_ref::fft_2d(dx_std, N, true);

    // Scan row 0: locate crest and trough of the (real) height field.
    int imax = 0, imin = 0;
    for (int i = 1; i < N; ++i) {
        if (h_std[i].real() > h_std[imax].real()) imax = i;
        if (h_std[i].real() < h_std[imin].real()) imin = i;
    }
    auto ddx_at = [&](int i) {
        return 0.5 * (dx_std[(i + 1) % N].real() - dx_std[(i - 1 + N) % N].real());
    };
    EXPECT_LT(ddx_at(imax), 0.0) << "Dx must converge at the crest";
    EXPECT_GT(ddx_at(imin), 0.0) << "Dx must diverge at the trough";
}
