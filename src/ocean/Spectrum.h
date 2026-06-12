#pragma once
#include <cstdint>
#include <vector>
#include <glm/glm.hpp>

namespace mo {

struct SpectrumParams {
    int   N = 256;
    float L = 250.0f;             // patch size in meters
    float wind_speed = 12.0f;     // m/s
    float wind_dir_rad = 0.5f;
    float amplitude = 1.0f;       // A in Phillips formula
    float swell = 0.0f;           // 0 = broad wind sea, 1 = long-crested swell
    uint32_t seed = 0xC0FFEEu;
};

// Returns N*N packed h0 + conjugate-symmetric pair:
//   data[i].xy = h0(k) (real, imag)
//   data[i].zw = h0(-k)* (real, imag)
std::vector<glm::vec4> generate_h0(const SpectrumParams& p);

// Analytic Phillips spectrum value at k. `swell` in [0,1] raises the
// directional spreading exponent (|k̂·ŵ|² -> |k̂·ŵ|^(2(1+3·swell))), narrowing
// the spread from broad wind sea toward long-crested swell; along-wind energy
// is unchanged.
float phillips(glm::vec2 k, glm::vec2 wind_dir, float wind_speed, float amplitude,
               float swell = 0.0f);

// Tessendorf horizontal-displacement spectrum:
//   D̂x(k) = -i · (kx/|k|) · ĥ(k),   D̂z(k) = -i · (kz/|k|) · ĥ(k)
// Centered-spectrum layout matching the GPU pipeline (gid -> ic = gid - N/2,
// k = 2π·ic/L). The DC bin and the unpaired Nyquist bins (row/col 0) are
// written as zero — the latter so the spectra stay Hermitian and the IFFT'd
// fields real. Mirrors what `spectrum_kernel` produces alongside h on the GPU;
// kept here so the formula is testable against the CPU FFT reference.
void displacement_spectrum_from_height(
    const std::vector<glm::vec2>& h_spectrum,
    int N, float L,
    std::vector<glm::vec2>& dx_spectrum,
    std::vector<glm::vec2>& dz_spectrum);
}
