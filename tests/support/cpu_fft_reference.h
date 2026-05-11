#pragma once
#include <complex>
#include <vector>
namespace mo::fft_ref {
using c64 = std::complex<double>;
void fft_1d(std::vector<c64>& x, bool inverse);
void fft_2d(std::vector<c64>& xy, int N, bool inverse);
}
