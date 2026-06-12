#pragma once
// Radix-2 DIT butterfly schedule shared between the GPU kernel
// (shaders/fft.metal) and the CPU parity test (tests/fft_parity_test.cpp).
// Tests must stay Metal-free, so the index/twiddle math lives here where a
// plain C++ translation unit can execute the exact arithmetic the GPU runs.

#ifdef __METAL_VERSION__
typedef uint fftc_uint;
#else
typedef unsigned int fftc_uint;
#endif

inline fftc_uint fftc_bit_reverse(fftc_uint x, fftc_uint bits) {
    fftc_uint y = 0;
    for (fftc_uint i = 0; i < bits; ++i) { y = (y << 1) | (x & 1u); x >>= 1u; }
    return y;
}

inline fftc_uint fftc_log2(fftc_uint n) {
    fftc_uint r = 0; while ((1u << r) < n) ++r; return r;
}

// One butterfly assignment for worker `local` (in [0, N/2)) at stage s (1-based):
// elements `a` and `b = a + m/2` combined with twiddle exp(i*angle).
struct FftcButterfly {
    fftc_uint a;
    fftc_uint b;
    float     angle;
};

inline FftcButterfly fftc_schedule(fftc_uint local, fftc_uint s) {
    fftc_uint m      = 1u << s;
    fftc_uint half_m = m >> 1u;
    fftc_uint k      = local & (half_m - 1u);
    FftcButterfly r;
    r.a = (local / half_m) * m + k;
    r.b = r.a + half_m;
    // +2π: inverse (synthesis) transform, unnormalized — the ocean pipeline
    // turns a spectrum into a field; post_fft.metal applies the 1/N² for the
    // row+column pair.
    r.angle = 6.283185 * (float)k / (float)m;
    return r;
}
