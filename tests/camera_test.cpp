#include <gtest/gtest.h>
#include "core/OrbitCamera.h"
#include <glm/gtc/matrix_access.hpp>

TEST(OrbitCamera, ViewTransformsTargetToOrigin) {
    mo::OrbitCamera c;
    c.set_target({10, 0, -5});
    glm::vec4 tv = c.view() * glm::vec4(10, 0, -5, 1);
    EXPECT_NEAR(tv.x, 0.0f, 1e-3f);
    EXPECT_NEAR(tv.y, 0.0f, 1e-3f);
}

TEST(OrbitCamera, ZoomDecreasesDistance) {
    mo::OrbitCamera c;
    float d0 = c.distance;
    c.zoom(2.0f);
    EXPECT_LT(c.distance, d0);
}

TEST(OrbitCamera, PitchClampsBelowPiOverTwo) {
    mo::OrbitCamera c;
    for (int i = 0; i < 1000; ++i) c.orbit(0.0f, 50.0f);
    EXPECT_LT(c.pitch_rad, 1.5f);
    EXPECT_GT(c.pitch_rad, -1.5f);
}
