#include "ocean/Spectrum.h"
#include <cmath>
#include <random>

namespace mo {

static constexpr float G = 9.81f;

float phillips(glm::vec2 k, glm::vec2 wind_dir, float wind_speed, float A) {
    float k2 = k.x*k.x + k.y*k.y;
    if (k2 < 1e-12f) return 0.0f;
    float k4 = k2 * k2;
    float L = wind_speed * wind_speed / G;
    float kw = (glm::length(k) > 0.0f ? glm::dot(glm::normalize(k), wind_dir) : 0.0f);
    float damping = std::exp(-k2 * (L * 0.001f) * (L * 0.001f));
    return A * std::exp(-1.0f / (k2 * L * L)) / k4 * (kw * kw) * damping;
}

std::vector<glm::vec4> generate_h0(const SpectrumParams& p) {
    std::vector<glm::vec4> out((size_t)p.N * p.N);
    std::mt19937 rng(p.seed);
    std::normal_distribution<float> nd(0.0f, 1.0f);
    glm::vec2 wd { std::cos(p.wind_dir_rad), std::sin(p.wind_dir_rad) };

    for (int j = 0; j < p.N; ++j) {
        for (int i = 0; i < p.N; ++i) {
            int  ic = i - p.N / 2;
            int  jc = j - p.N / 2;
            glm::vec2 k = { 2.0f * 3.1415926535f * (float)ic / p.L,
                             2.0f * 3.1415926535f * (float)jc / p.L };
            float ph  = phillips( k, wd, p.wind_speed, p.amplitude);
            float phm = phillips(-k, wd, p.wind_speed, p.amplitude);
            float kr = nd(rng), ki = nd(rng);
            float mr = nd(rng), mi = nd(rng);
            float s = 1.0f / std::sqrt(2.0f);
            glm::vec4 v;
            v.x = s * kr * std::sqrt(ph);
            v.y = s * ki * std::sqrt(ph);
            v.z = s * mr * std::sqrt(phm); // h0(-k)* approximated; conjugate handled in shader
            v.w = -s * mi * std::sqrt(phm);
            out[(size_t)j * p.N + i] = v;
        }
    }
    return out;
}

}
