#include "core/OrbitCamera.h"
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/ext/matrix_transform.hpp>
#include <glm/ext/matrix_clip_space.hpp>
#include <algorithm>
#include <cmath>

namespace mo {

OrbitCamera::OrbitCamera() = default;

void OrbitCamera::orbit(float dx, float dy) {
    yaw_rad   += dx * 0.005f;
    pitch_rad += dy * 0.005f;
    const float lim = 1.4999f;
    pitch_rad = std::clamp(pitch_rad, -lim, lim);
}

void OrbitCamera::zoom(float scroll) {
    distance *= std::exp(-scroll * 0.1f);
    distance = std::clamp(distance, 1.0f, 5000.0f);
}

void OrbitCamera::set_target(glm::vec3 t) { target_ = t; }
void OrbitCamera::set_aspect(float a)      { aspect_ = a; }
void OrbitCamera::set_fov_deg(float f)     { fov_deg_ = f; }

glm::vec3 OrbitCamera::position() const {
    float cp = std::cos(pitch_rad), sp = std::sin(pitch_rad);
    float cy = std::cos(yaw_rad),   sy = std::sin(yaw_rad);
    glm::vec3 off { distance * cp * sy, distance * sp, distance * cp * cy };
    return target_ + off;
}

glm::mat4 OrbitCamera::view() const {
    return glm::lookAt(position(), target_, glm::vec3(0,1,0));
}
glm::mat4 OrbitCamera::proj() const {
    return glm::perspective(glm::radians(fov_deg_), aspect_, near_, far_);
}
glm::mat4 OrbitCamera::view_proj() const { return proj() * view(); }

}
