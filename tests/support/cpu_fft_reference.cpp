#include "support/cpu_fft_reference.h"
#include <cmath>
namespace mo::fft_ref {

void fft_1d(std::vector<c64>& x, bool inverse) {
    size_t N = x.size();
    if (N <= 1) return;
    // bit-reverse permutation
    for (size_t i = 1, j = 0; i < N; ++i) {
        size_t bit = N >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(x[i], x[j]);
    }
    for (size_t len = 2; len <= N; len <<= 1) {
        double theta = (inverse ? 2.0 : -2.0) * M_PI / (double)len;
        c64 wlen(std::cos(theta), std::sin(theta));
        for (size_t i = 0; i < N; i += len) {
            c64 w(1, 0);
            for (size_t j = 0; j < len / 2; ++j) {
                c64 u = x[i + j], v = x[i + j + len / 2] * w;
                x[i + j] = u + v;
                x[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
    if (inverse) for (auto& v : x) v /= (double)N;
}

void fft_2d(std::vector<c64>& xy, int N, bool inverse) {
    std::vector<c64> row(N);
    for (int j = 0; j < N; ++j) {
        for (int i = 0; i < N; ++i) row[i] = xy[j * N + i];
        fft_1d(row, inverse);
        for (int i = 0; i < N; ++i) xy[j * N + i] = row[i];
    }
    std::vector<c64> col(N);
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) col[j] = xy[j * N + i];
        fft_1d(col, inverse);
        for (int j = 0; j < N; ++j) xy[j * N + i] = col[j];
    }
}
}
