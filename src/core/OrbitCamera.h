#pragma once
#include <glm/glm.hpp>

namespace mo {
class OrbitCamera {
public:
    OrbitCamera();
    void orbit(float dx, float dy);          // mouse drag in pixels
    void zoom(float scroll);                  // scroll wheel units
    void set_target(glm::vec3 t);
    void set_aspect(float a);
    void set_fov_deg(float f);

    glm::vec3 position() const;
    glm::mat4 view() const;
    glm::mat4 proj() const;
    glm::mat4 view_proj() const;

    float yaw_rad = 0.0f;
    float pitch_rad = 0.3f;
    float distance = 80.0f;
private:
    glm::vec3 target_ {0.0f};
    float aspect_ = 16.0f/9.0f;
    float fov_deg_ = 55.0f;
    float near_ = 0.5f;
    float far_  = 5000.0f;
};
}
