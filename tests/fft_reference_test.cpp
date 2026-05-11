#include <gtest/gtest.h>
#include "support/cpu_fft_reference.h"
#include <cmath>

using namespace mo::fft_ref;

TEST(FftRef, RoundTrip8) {
    std::vector<c64> x(8);
    for (int i = 0; i < 8; ++i) x[i] = c64(std::sin(0.7 * i), 0.1 * i);
    auto orig = x;
    fft_1d(x, false);
    fft_1d(x, true);
    for (int i = 0; i < 8; ++i) {
        EXPECT_NEAR(x[i].real(), orig[i].real(), 1e-9);
        EXPECT_NEAR(x[i].imag(), orig[i].imag(), 1e-9);
    }
}

TEST(FftRef, ImpulseProducesFlatSpectrum) {
    std::vector<c64> x(8, 0); x[0] = 1.0;
    fft_1d(x, false);
    for (auto& v : x) EXPECT_NEAR(std::abs(v), 1.0, 1e-9);
}

TEST(FftRef, RoundTrip2D8x8) {
    int N = 8;
    std::vector<c64> img(N * N);
    for (int j = 0; j < N; ++j) for (int i = 0; i < N; ++i)
        img[j*N+i] = c64(std::sin(0.2*i) * std::cos(0.3*j), 0);
    auto orig = img;
    fft_2d(img, N, false);
    fft_2d(img, N, true);
    for (int k = 0; k < N*N; ++k) {
        EXPECT_NEAR(img[k].real(), orig[k].real(), 1e-8);
    }
}
