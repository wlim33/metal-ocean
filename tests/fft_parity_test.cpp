#include <gtest/gtest.h>
#include "support/cpu_fft_reference.h"
#include "fft_common.h"
#include <complex>
#include <random>
#include <vector>

using mo::fft_ref::c64;

// Executes the exact data flow of fft_kernel in shaders/fft.metal: bit-reversed
// load into "threadgroup memory", then for each stage every worker local < N/2
// applies the shared schedule's butterfly. With correct indexing each (a, b)
// pair is owned by exactly one worker per stage, so sequential in-place
// execution here matches the barrier-per-stage GPU execution.
static std::vector<c64> fft_as_gpu_kernel(const std::vector<c64>& in) {
    fftc_uint N = (fftc_uint)in.size();
    fftc_uint bits = fftc_log2(N);
    std::vector<c64> tg(N);
    for (fftc_uint i = 0; i < N; ++i) tg[fftc_bit_reverse(i, bits)] = in[i];
    for (fftc_uint s = 1; s <= bits; ++s) {
        for (fftc_uint local = 0; local < N / 2; ++local) {
            FftcButterfly bf = fftc_schedule(local, s);
            c64 w(std::cos((double)bf.angle), std::sin((double)bf.angle));
            c64 a = tg[bf.a];
            c64 t = w * tg[bf.b];
            tg[bf.a] = a + t;
            tg[bf.b] = a - t;
        }
    }
    return tg;
}

// The ocean pipeline needs an inverse transform (synthesis: spectrum -> field).
// fft_ref::fft_1d(x, true) is a normalized inverse (includes 1/N); the GPU
// kernel is unnormalized (post_fft.metal applies 1/N² for the 2D pair), so the
// kernel's output must equal N * reference.
TEST(FftParity, GpuScheduleMatchesReferenceInverse) {
    std::mt19937 rng(1234);
    std::normal_distribution<double> nd(0.0, 1.0);
    for (fftc_uint N : {8u, 64u, 256u}) {
        std::vector<c64> x(N);
        for (auto& v : x) v = c64(nd(rng), nd(rng));

        std::vector<c64> gpu = fft_as_gpu_kernel(x);
        std::vector<c64> ref = x;
        mo::fft_ref::fft_1d(ref, true);

        for (fftc_uint i = 0; i < N; ++i) {
            EXPECT_NEAR(gpu[i].real(), ref[i].real() * (double)N, 1e-2)
                << "N=" << N << " bin=" << i;
            EXPECT_NEAR(gpu[i].imag(), ref[i].imag() * (double)N, 1e-2)
                << "N=" << N << " bin=" << i;
        }
    }
}

// Every stage must assign each butterfly pair to exactly one worker: the N/2
// workers' (a, b) pairs partition [0, N) with no duplicates. The original
// kernel bug ((local / m) * m instead of (local / half_m) * m) computed some
// butterflies twice (a data race on threadgroup memory) and skipped others.
TEST(FftParity, ScheduleCoversAllPairsExactlyOnce) {
    for (fftc_uint N : {8u, 256u}) {
        fftc_uint bits = fftc_log2(N);
        for (fftc_uint s = 1; s <= bits; ++s) {
            std::vector<int> touched(N, 0);
            for (fftc_uint local = 0; local < N / 2; ++local) {
                FftcButterfly bf = fftc_schedule(local, s);
                ASSERT_LT(bf.a, N);
                ASSERT_LT(bf.b, N);
                touched[bf.a]++;
                touched[bf.b]++;
            }
            for (fftc_uint i = 0; i < N; ++i)
                EXPECT_EQ(touched[i], 1) << "N=" << N << " stage=" << s << " elem=" << i;
        }
    }
}
