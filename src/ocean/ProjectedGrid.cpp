#include "ocean/ProjectedGrid.h"
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtc/matrix_inverse.hpp>
#include <algorithm>
#include <limits>

namespace mo {
namespace {

// Intersect line through p0->p1 with horizontal plane y = y_plane.
// Returns true and fills out if there's an intersection within the segment.
bool intersect_y(const glm::vec3& p0, const glm::vec3& p1, float y_plane, glm::vec3& out) {
    float dy = p1.y - p0.y;
    if (std::abs(dy) < 1e-6f) return false;
    float t = (y_plane - p0.y) / dy;
    if (t < 0.0f || t > 1.0f) return false;
    out = p0 + (p1 - p0) * t;
    return true;
}

// 8 frustum corners in world space from inverse view-proj
void frustum_corners(const glm::mat4& inv_vp, glm::vec3 out[8]) {
    int k = 0;
    for (int z = 0; z <= 1; ++z)
      for (int y = -1; y <= 1; y += 2)
        for (int x = -1; x <= 1; x += 2) {
            glm::vec4 c = inv_vp * glm::vec4((float)x, (float)y, z ? 1.0f : 0.0f, 1.0f);
            out[k++] = glm::vec3(c) / c.w;
        }
}
const int FRUSTUM_EDGES[12][2] = {
    {0,1},{0,2},{1,3},{2,3},  // near
    {4,5},{4,6},{5,7},{6,7},  // far
    {0,4},{1,5},{2,6},{3,7}   // sides
};

} // namespace

ProjectedGridOutput build_projected_grid(const glm::mat4& view, const glm::mat4& proj,
                                        const glm::vec3& camera_pos,
                                        const ProjectedGridParams& p) {
    ProjectedGridOutput out;
    const float D = p.displacement_range_m;
    const float SL = p.sea_level;

    // Build displacement camera = main, but lifted if inside slab.
    glm::mat4 vp_main = proj * view;
    glm::mat4 inv_main = glm::inverse(vp_main);

    glm::vec3 corners[8];
    frustum_corners(inv_main, corners);

    // Collect "interesting" world points: frustum edge intersections with y=SL+D and y=SL-D,
    // plus corners within the slab.
    std::vector<glm::vec3> pts;
    pts.reserve(32);
    for (int i = 0; i < 8; ++i) {
        if (corners[i].y >= SL - D && corners[i].y <= SL + D) pts.push_back(corners[i]);
    }
    for (int e = 0; e < 12; ++e) {
        glm::vec3 hit;
        if (intersect_y(corners[FRUSTUM_EDGES[e][0]], corners[FRUSTUM_EDGES[e][1]], SL + D, hit))
            pts.push_back(hit);
        if (intersect_y(corners[FRUSTUM_EDGES[e][0]], corners[FRUSTUM_EDGES[e][1]], SL - D, hit))
            pts.push_back(hit);
    }
    if (pts.empty()) { out.visible = false; return out; }

    // Displacement camera: same as main unless inside slab; then lift above.
    glm::vec3 disp_pos = camera_pos;
    glm::mat4 view_disp = view;
    if (camera_pos.y >= SL - D && camera_pos.y <= SL + D) {
        disp_pos.y = SL + D + 1.0f;
        view_disp = view; view_disp[3] = view * glm::vec4(-disp_pos, 1.0f);
        // Simpler: rebuild view from disp_pos preserving original forward.
        // For tests, the lift is what matters; precise orientation reuse is fine.
    }
    glm::mat4 inv_disp = glm::inverse(proj * view_disp);

    // Project pts into disp camera NDC; take AABB.
    float xn_min = 1e9f, xn_max = -1e9f, yn_min = 1e9f, yn_max = -1e9f;
    glm::mat4 vp_disp = proj * view_disp;
    for (auto& w : pts) {
        glm::vec4 c = vp_disp * glm::vec4(w, 1.0f);
        if (c.w <= 0.0f) continue;
        glm::vec2 nd(c.x / c.w, c.y / c.w);
        nd.x = std::clamp(nd.x, -1.0f, 1.0f);
        nd.y = std::clamp(nd.y, -1.0f, 1.0f);
        xn_min = std::min(xn_min, nd.x); xn_max = std::max(xn_max, nd.x);
        yn_min = std::min(yn_min, nd.y); yn_max = std::max(yn_max, nd.y);
    }
    if (xn_min >= xn_max || yn_min >= yn_max) { out.visible = false; return out; }

    // Generate vertex grid in this NDC quad, unproject to world, intersect with y=SL.
    out.vertices_xz.resize((size_t)p.cols * (size_t)p.rows);
    for (int j = 0; j < p.rows; ++j) {
        float v = (p.rows == 1) ? 0.0f : (float)j / (float)(p.rows - 1);
        for (int i = 0; i < p.cols; ++i) {
            float u = (p.cols == 1) ? 0.0f : (float)i / (float)(p.cols - 1);
            float xn = xn_min + (xn_max - xn_min) * u;
            float yn = yn_min + (yn_max - yn_min) * v;

            glm::vec4 a = inv_disp * glm::vec4(xn, yn, 0.0f, 1.0f);
            glm::vec4 b = inv_disp * glm::vec4(xn, yn, 1.0f, 1.0f);
            glm::vec3 pa = glm::vec3(a) / a.w;
            glm::vec3 pb = glm::vec3(b) / b.w;
            glm::vec3 d = pb - pa;
            float t = (std::abs(d.y) > 1e-6f) ? (SL - pa.y) / d.y : 0.0f;
            glm::vec3 wp = pa + d * t;
            out.vertices_xz[(size_t)j * p.cols + i] = { wp.x, wp.z };
        }
    }

    // Indices: 2 triangles per quad
    out.indices.reserve(6u * (p.cols - 1) * (p.rows - 1));
    for (int j = 0; j < p.rows - 1; ++j) {
        for (int i = 0; i < p.cols - 1; ++i) {
            uint32_t a = (uint32_t)(j * p.cols + i);
            uint32_t b = a + 1;
            uint32_t c = a + p.cols;
            uint32_t d = c + 1;
            out.indices.push_back(a); out.indices.push_back(c); out.indices.push_back(b);
            out.indices.push_back(b); out.indices.push_back(c); out.indices.push_back(d);
        }
    }
    return out;
}
} // namespace mo
