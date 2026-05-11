#include <gtest/gtest.h>
#include "ocean/ProjectedGrid.h"
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/ext/matrix_transform.hpp>
#include <glm/ext/matrix_clip_space.hpp>

static glm::mat4 proj_mat(float aspect = 16.0f/9.0f) {
    return glm::perspective(glm::radians(55.0f), aspect, 0.5f, 5000.0f);
}

TEST(ProjectedGrid, DimensionsMatchParams) {
    glm::vec3 pos(0, 50, 0);
    auto v = glm::lookAt(pos, glm::vec3(0,0,-100), glm::vec3(0,1,0));
    mo::ProjectedGridParams p; p.cols = 16; p.rows = 8;
    auto out = mo::build_projected_grid(v, proj_mat(), pos, p);
    EXPECT_EQ(out.vertices_xz.size(), 16u * 8u);
    EXPECT_EQ(out.indices.size(), 6u * 15u * 7u);
}

TEST(ProjectedGrid, LooksDownProducesVerticesAroundCamera) {
    glm::vec3 pos(0, 50, 0);
    auto v = glm::lookAt(pos, glm::vec3(0, 0, 0), glm::vec3(0, 0, -1));
    mo::ProjectedGridParams p;
    auto out = mo::build_projected_grid(v, proj_mat(), pos, p);
    ASSERT_TRUE(out.visible);
    float minD = 1e9f;
    for (auto& w : out.vertices_xz) minD = std::min(minD, glm::length(w));
    EXPECT_LT(minD, 60.0f); // some vertex within ~camera height of origin
}

TEST(ProjectedGrid, DeterministicForFixedInput) {
    glm::vec3 pos(0, 30, 20);
    auto v = glm::lookAt(pos, glm::vec3(0,0,0), glm::vec3(0,1,0));
    auto a = mo::build_projected_grid(v, proj_mat(), pos, {});
    auto b = mo::build_projected_grid(v, proj_mat(), pos, {});
    ASSERT_EQ(a.vertices_xz.size(), b.vertices_xz.size());
    for (size_t i = 0; i < a.vertices_xz.size(); ++i) {
        EXPECT_FLOAT_EQ(a.vertices_xz[i].x, b.vertices_xz[i].x);
        EXPECT_FLOAT_EQ(a.vertices_xz[i].y, b.vertices_xz[i].y);
    }
}

TEST(ProjectedGrid, CameraInsideSlabLiftsDisplacementCamera) {
    // pos near sea level - should still produce vertices
    glm::vec3 pos(0, 1.0f, 0);
    auto v = glm::lookAt(pos, glm::vec3(0, 1.0f, -100), glm::vec3(0, 1, 0));
    mo::ProjectedGridParams p; p.displacement_range_m = 8.0f;
    auto out = mo::build_projected_grid(v, proj_mat(), pos, p);
    EXPECT_TRUE(out.visible);
    EXPECT_FALSE(out.vertices_xz.empty());
}

TEST(ProjectedGrid, IndicesReferenceValidVertices) {
    glm::vec3 pos(0, 50, 0);
    auto v = glm::lookAt(pos, glm::vec3(0,0,-100), glm::vec3(0,1,0));
    auto out = mo::build_projected_grid(v, proj_mat(), pos, {});
    for (uint32_t i : out.indices) EXPECT_LT(i, out.vertices_xz.size());
}
