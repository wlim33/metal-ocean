#include "ocean/Spectrum.h"
#include <cmath>
#include <random>

namespace mo {

static constexpr float G = 9.81f;

float phillips(glm::vec2 k, glm::vec2 wind_dir, float wind_speed, float A,
               float swell) {
    float k2 = k.x*k.x + k.y*k.y;
    if (k2 < 1e-12f) return 0.0f;
    float k4 = k2 * k2;
    float L = wind_speed * wind_speed / G;
    float kw = (glm::length(k) > 0.0f ? glm::dot(glm::normalize(k), wind_dir) : 0.0f);
    float damping = std::exp(-k2 * (L * 0.001f) * (L * 0.001f));
    float spread = std::pow(kw * kw, 1.0f + 3.0f * swell);
    return A * std::exp(-1.0f / (k2 * L * L)) / k4 * spread * damping;
}

void displacement_spectrum_from_height(
    const std::vector<glm::vec2>& h, int N, float L,
    std::vector<glm::vec2>& dx, std::vector<glm::vec2>& dz)
{
    const float two_pi = 6.2831853071795864769f;
    dx.assign((size_t)N * N, glm::vec2(0.0f));
    dz.assign((size_t)N * N, glm::vec2(0.0f));
    for (int j = 0; j < N; ++j) {
        for (int i = 0; i < N; ++i) {
            int ic = i - N / 2;
            int jc = j - N / 2;
            if (ic == 0 && jc == 0) continue;
            // Nyquist bins (ic or jc == -N/2) are their own mirror partner, so
            // -i·k̂·ĥ would be purely imaginary there — breaking the Hermitian
            // symmetry that keeps the IFFT'd displacement fields real. Zero them.
            if (i == 0 || j == 0) continue;
            float kx = two_pi * (float)ic / L;
            float kz = two_pi * (float)jc / L;
            float kmag = std::sqrt(kx * kx + kz * kz);
            glm::vec2 hk = h[(size_t)j * N + i];
            // -i · (a + i·b) = b - i·a
            glm::vec2 minus_i_h{ hk.y, -hk.x };
            dx[(size_t)j * N + i] = (kx / kmag) * minus_i_h;
            dz[(size_t)j * N + i] = (kz / kmag) * minus_i_h;
        }
    }
}

std::vector<glm::vec4> generate_h0(const SpectrumParams& p) {
    std::vector<glm::vec4> out((size_t)p.N * p.N);
    std::mt19937 rng(p.seed);
    std::normal_distribution<float> nd(0.0f, 1.0f);
    glm::vec2 wd { std::cos(p.wind_dir_rad), std::sin(p.wind_dir_rad) };

    // Pass 1: independent draws for h0(k) in xy.
    for (int j = 0; j < p.N; ++j) {
        for (int i = 0; i < p.N; ++i) {
            int  ic = i - p.N / 2;
            int  jc = j - p.N / 2;
            glm::vec2 k = { 2.0f * 3.1415926535f * (float)ic / p.L,
                             2.0f * 3.1415926535f * (float)jc / p.L };
            float ph = phillips(k, wd, p.wind_speed, p.amplitude, p.swell);
            float kr = nd(rng), ki = nd(rng);
            float s = 1.0f / std::sqrt(2.0f);
            out[(size_t)j * p.N + i].x = s * kr * std::sqrt(ph);
            out[(size_t)j * p.N + i].y = s * ki * std::sqrt(ph);
        }
    }
    // Pass 2: zw = h0(-k)* taken from the mirrored bin, so that
    // h̃(k,t) = h0(k)e^{iωt} + h0*(-k)e^{-iωt} is Hermitian and the IFFT'd
    // height field is real (the pipeline reads only the real channel).
    for (int j = 0; j < p.N; ++j) {
        for (int i = 0; i < p.N; ++i) {
            int im = (p.N - i) % p.N;
            int jm = (p.N - j) % p.N;
            const glm::vec4& m = out[(size_t)jm * p.N + im];
            out[(size_t)j * p.N + i].z =  m.x;
            out[(size_t)j * p.N + i].w = -m.y;
        }
    }
    return out;
}

}
