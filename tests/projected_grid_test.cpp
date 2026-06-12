#include <gtest/gtest.h>
#include "ocean/ProjectedGrid.h"
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/ext/matrix_transform.hpp>
#include <glm/ext/matrix_clip_space.hpp>
#include <cmath>
#include <vector>

static glm::mat4 proj_mat(float aspect = 16.0f/9.0f) {
    return glm::perspective(glm::radians(55.0f), aspect, 0.5f, 5000.0f);
}

namespace {

// The grid footprint boundary as a closed polygon in world (x, z).
std::vector<glm::vec2> world_rim(const mo::ProjectedGridOutput& g, int cols, int rows) {
    std::vector<glm::vec2> poly;
    auto push = [&](int i, int j) { poly.push_back(g.vertices_xz[(size_t)j * cols + i]); };
    for (int i = 0; i < cols; ++i)      push(i, 0);
    for (int j = 1; j < rows; ++j)      push(cols - 1, j);
    for (int i = cols - 2; i >= 0; --i) push(i, rows - 1);
    for (int j = rows - 2; j >= 1; --j) push(0, j);
    return poly;
}

bool point_in_polygon(const std::vector<glm::vec2>& poly, glm::vec2 q) {
    bool in = false;
    for (size_t i = 0, n = poly.size(), j = n - 1; i < n; j = i++) {
        if (((poly[i].y > q.y) != (poly[j].y > q.y)) &&
            (q.x < (poly[j].x - poly[i].x) * (q.y - poly[i].y) /
                       (poly[j].y - poly[i].y) + poly[i].x))
            in = !in;
    }
    return in;
}

// Rest position a grid vertex must have so that, displaced by uniform offset
// d, it lands exactly on the main-camera ray through NDC sample q: intersect
// the ray with the plane y = d.y, then subtract the horizontal displacement.
// Returns false if the ray never reaches that plane (sample sees sky).
bool required_rest_xz(const glm::mat4& inv_vp, glm::vec2 q, glm::vec3 d, glm::vec2& out) {
    glm::vec4 a = inv_vp * glm::vec4(q.x, q.y, 0.0f, 1.0f);
    glm::vec4 b = inv_vp * glm::vec4(q.x, q.y, 1.0f, 1.0f);
    glm::vec3 pa = glm::vec3(a) / a.w, pb = glm::vec3(b) / b.w;
    glm::vec3 dir = pb - pa;
    if (std::abs(dir.y) < 1e-6f) return false;
    float t = (d.y - pa.y) / dir.y;
    if (t < 0.0f) return false;
    glm::vec3 hit = pa + dir * t;
    out = { hit.x - d.x, hit.z - d.z };
    return true;
}

} // namespace

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

// With the camera inside the displacement slab, the lifted projector must
// still cover the visible water (guards the lift against coverage holes).
TEST(ProjectedGrid, LowCameraGridStillCoversWindowBottom) {
    glm::vec3 pos(0, 4, 80); // 4 m above water, inside the default +-8 m slab
    auto v = glm::lookAt(pos, glm::vec3(0, 0, 0), glm::vec3(0, 1, 0));
    mo::ProjectedGridParams p; p.cols = 65; p.rows = 65;
    auto out = mo::build_projected_grid(v, proj_mat(), pos, p);
    ASSERT_TRUE(out.visible);
    auto rim = world_rim(out, p.cols, p.rows);
    glm::mat4 inv_vp = glm::inverse(proj_mat() * v);
    for (float x = -0.9f; x <= 0.9f; x += 0.3f) {
        for (float y : {-0.95f, -0.5f}) {
            glm::vec2 r;
            ASSERT_TRUE(required_rest_xz(inv_vp, {x, y}, glm::vec3(0), r));
            EXPECT_TRUE(point_in_polygon(rim, r))
                << "window sample (" << x << ", " << y << ") uncovered";
        }
    }
}

// Regression: the in-slab lift used to double-count the camera translation,
// placing the projector ~a camera-distance away and spreading the grid over
// a far larger footprint than the screen needs. Far from the origin the
// error is extreme (<5% of vertices on screen); the correct lift keeps a
// healthy fraction useful.
TEST(ProjectedGrid, LowCameraKeepsMostVerticesOnScreen) {
    glm::vec3 pos(0, 4, 2000);
    auto v = glm::lookAt(pos, glm::vec3(0, 0, 0), glm::vec3(0, 1, 0));
    mo::ProjectedGridParams p; p.cols = 65; p.rows = 65;
    auto out = mo::build_projected_grid(v, proj_mat(), pos, p);
    ASSERT_TRUE(out.visible);
    glm::mat4 vp = proj_mat() * v;
    int on_screen = 0;
    for (auto& xz : out.vertices_xz) {
        glm::vec4 c = vp * glm::vec4(xz.x, 0.0f, xz.y, 1.0f);
        if (c.w > 0.0f && std::abs(c.x / c.w) <= 1.0f && std::abs(c.y / c.w) <= 1.0f)
            ++on_screen;
    }
    float frac = (float)on_screen / (float)out.vertices_xz.size();
    EXPECT_GE(frac, 0.3f) << "only " << frac * 100.0f << "% of grid vertices on screen";
}

// Regression: boundary vertices used to sit exactly on window-edge rays, so
// any wave displacement opened background slivers along the window borders.
// The mesh displaced by any uniform offset within +-D must still cover the
// window edges wherever water is visible.
TEST(ProjectedGrid, WindowEdgesCoveredUnderDisplacement) {
    glm::vec3 pos(0, 80.0f * std::sin(0.3f), 80.0f * std::cos(0.3f)); // OrbitCamera default
    auto v = glm::lookAt(pos, glm::vec3(0), glm::vec3(0, 1, 0));
    mo::ProjectedGridParams p; p.cols = 65; p.rows = 65; p.displacement_range_m = 4.0f;
    auto out = mo::build_projected_grid(v, proj_mat(), pos, p);
    ASSERT_TRUE(out.visible);
    const float D = p.displacement_range_m;
    auto rim = world_rim(out, p.cols, p.rows);
    glm::mat4 inv_vp = glm::inverse(proj_mat() * v);
    for (int c = 0; c < 8; ++c) {
        glm::vec3 d((c & 1) ? D : -D, (c & 2) ? D : -D, (c & 4) ? D : -D);
        auto check = [&](float x, float y) {
            glm::vec2 r;
            if (!required_rest_xz(inv_vp, {x, y}, d, r)) return; // sample sees sky
            EXPECT_TRUE(point_in_polygon(rim, r))
                << "window sample (" << x << ", " << y << ") uncovered, corner=" << c;
        };
        for (float x = -0.9f; x <= 0.9f; x += 0.3f) check(x, -0.95f);
        for (float y = -0.9f; y <= 0.15f; y += 0.25f) { check(-0.95f, y); check(0.95f, y); }
    }
}

TEST(ProjectedGrid, IndicesReferenceValidVertices) {
    glm::vec3 pos(0, 50, 0);
    auto v = glm::lookAt(pos, glm::vec3(0,0,-100), glm::vec3(0,1,0));
    auto out = mo::build_projected_grid(v, proj_mat(), pos, {});
    for (uint32_t i : out.indices) EXPECT_LT(i, out.vertices_xz.size());
}
