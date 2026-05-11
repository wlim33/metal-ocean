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
    uint32_t seed = 0xC0FFEEu;
};

// Returns N*N packed h0 + conjugate-symmetric pair:
//   data[i].xy = h0(k) (real, imag)
//   data[i].zw = h0(-k)* (real, imag)
std::vector<glm::vec4> generate_h0(const SpectrumParams& p);

// Analytic Phillips spectrum value at k (for tests).
float phillips(glm::vec2 k, glm::vec2 wind_dir, float wind_speed, float amplitude);
}
