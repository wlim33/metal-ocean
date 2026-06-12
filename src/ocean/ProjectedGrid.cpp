#include "ocean/ProjectedGrid.h"
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtc/matrix_inverse.hpp>
#include <algorithm>

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

// Camera ray through NDC (xn, yn): origin at the z=0 unprojection, pointing
// toward the z=1 unprojection.
struct Ray { glm::vec3 origin, dir; };
Ray ndc_ray(const glm::mat4& inv_vp, float xn, float yn) {
    glm::vec4 a = inv_vp * glm::vec4(xn, yn, 0.0f, 1.0f);
    glm::vec4 b = inv_vp * glm::vec4(xn, yn, 1.0f, 1.0f);
    glm::vec3 pa = glm::vec3(a) / a.w;
    return { pa, glm::vec3(b) / b.w - pa };
}

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

    // Displacement camera: same as main unless inside slab; then lift above,
    // keeping the main camera's orientation (rebuild the translation column
    // from the rotation so the projector really sits at disp_pos).
    glm::vec3 disp_pos = camera_pos;
    glm::mat4 view_disp = view;
    if (camera_pos.y >= SL - D && camera_pos.y <= SL + D) {
        disp_pos.y = SL + D + 1.0f;
        view_disp[3] = glm::vec4(glm::mat3(view) * -disp_pos, 1.0f);
    }
    glm::mat4 inv_disp = glm::inverse(proj * view_disp);

    // AABB over points projected into disp-camera NDC, clamped per source.
    float xn_min = 1e9f, xn_max = -1e9f, yn_min = 1e9f, yn_max = -1e9f;
    glm::mat4 vp_disp = proj * view_disp;
    auto fold = [&](const glm::vec3& w, float lim) {
        glm::vec4 c = vp_disp * glm::vec4(w, 1.0f);
        if (c.w <= 0.0f) return;
        glm::vec2 nd(c.x / c.w, c.y / c.w);
        nd.x = std::clamp(nd.x, -lim, lim);
        nd.y = std::clamp(nd.y, -lim, lim);
        xn_min = std::min(xn_min, nd.x); xn_max = std::max(xn_max, nd.x);
        yn_min = std::min(yn_min, nd.y); yn_max = std::max(yn_max, nd.y);
    };

    // Each point is inflated to the corners of its +-D cube so the grid also
    // reaches rest positions whose displaced surface enters the frustum;
    // otherwise boundary vertices sit exactly on window-edge rays and any
    // displacement opens background slivers along the window borders. The
    // clamp bounds the grid stretch when near-camera points project far
    // outside the screen; displacements needing more than PAD_NDC_MAX of
    // screen-space margin can still open gaps, which only happens with the
    // camera essentially inside the waves.
    constexpr float PAD_NDC_MAX = 0.75f;
    for (auto& w : pts)
        for (int c = 0; c < 8; ++c)
            fold(w + glm::vec3((c & 1) ? D : -D, (c & 2) ? D : -D, (c & 4) ? D : -D),
                 1.0f + PAD_NDC_MAX);

    // Rest-pose coverage requirement: wherever the main camera's window
    // border sees the sea plane, the grid must reach — the +-D inflation
    // above is only a best-effort margin once the camera sits inside the
    // slab (the lifted projector needs steeper angles than PAD_NDC_MAX
    // allows to reach water near the main camera). Sample border rays,
    // intersect with y=SL, and fold their projections into the AABB.
    constexpr float REQ_LIM = 4.0f; // bounds grid stretch in degenerate poses
    for (int k = 0; k <= 8; ++k) {
        float s = -1.0f + 0.25f * (float)k;
        for (auto [xn, yn] : {std::pair{s, -1.0f}, {s, 1.0f}, {-1.0f, s}, {1.0f, s}}) {
            Ray r = ndc_ray(inv_main, xn, yn);
            if (std::abs(r.dir.y) < 1e-6f) continue;
            float t = (SL - r.origin.y) / r.dir.y;
            if (t >= 0.0f) fold(r.origin + r.dir * t, REQ_LIM);
        }
    }

    // Rays at or above the displacement camera's horizon never hit the sea
    // plane in front of it (the plane intersection below walks backward),
    // so cap the AABB top at the horizon line (no camera roll in this app).
    glm::vec3 fwd = -glm::transpose(glm::mat3(view_disp))[2];
    glm::vec3 fwd_h(fwd.x, 0.0f, fwd.z);
    if (glm::dot(fwd_h, fwd_h) > 1e-8f) {
        glm::vec4 h = vp_disp * glm::vec4(disp_pos + glm::normalize(fwd_h) * 1e6f, 1.0f);
        if (h.w > 0.0f) yn_max = std::min(yn_max, h.y / h.w - 1e-4f);
    }

    if (xn_min >= xn_max || yn_min >= yn_max) { out.visible = false; return out; }

    // Generate vertex grid in this NDC quad, unproject to world, intersect
    // with y=SL. Unprojection is linear in clip space, so for fixed z
    // inv_disp * (xn, yn, z, 1) is a bilinear function of (xn, yn) — lerping
    // the four transformed corners BEFORE the perspective divide is exact,
    // replacing two mat4 multiplies per vertex with two lerps.
    out.vertices_xz.resize((size_t)p.cols * (size_t)p.rows);
    auto corner = [&](float xn, float yn, float z) {
        return inv_disp * glm::vec4(xn, yn, z, 1.0f);
    };
    const glm::vec4 a00 = corner(xn_min, yn_min, 0.f), a10 = corner(xn_max, yn_min, 0.f);
    const glm::vec4 a01 = corner(xn_min, yn_max, 0.f), a11 = corner(xn_max, yn_max, 0.f);
    const glm::vec4 b00 = corner(xn_min, yn_min, 1.f), b10 = corner(xn_max, yn_min, 1.f);
    const glm::vec4 b01 = corner(xn_min, yn_max, 1.f), b11 = corner(xn_max, yn_max, 1.f);
    for (int j = 0; j < p.rows; ++j) {
        float v = (p.rows == 1) ? 0.0f : (float)j / (float)(p.rows - 1);
        glm::vec4 a0 = glm::mix(a00, a01, v), a1 = glm::mix(a10, a11, v);
        glm::vec4 b0 = glm::mix(b00, b01, v), b1 = glm::mix(b10, b11, v);
        for (int i = 0; i < p.cols; ++i) {
            float u = (p.cols == 1) ? 0.0f : (float)i / (float)(p.cols - 1);
            glm::vec4 ac = glm::mix(a0, a1, u);
            glm::vec4 bc = glm::mix(b0, b1, u);
            glm::vec3 pa = glm::vec3(ac) / ac.w;
            glm::vec3 dir = glm::vec3(bc) / bc.w - pa;
            float t = (std::abs(dir.y) > 1e-6f) ? (SL - pa.y) / dir.y : 0.0f;
            glm::vec3 wp = pa + dir * t;
            out.vertices_xz[(size_t)j * p.cols + i] = { wp.x, wp.z };
        }
    }

    // Indices: 2 triangles per quad. Content depends only on (cols, rows),
    // which rarely changes, so rebuild only on a topology change and hand out
    // copies of the cached buffer.
    static std::vector<uint32_t> cache;
    static int ck_cols = -1, ck_rows = -1;
    if (ck_cols != p.cols || ck_rows != p.rows) {
        cache.clear();
        cache.reserve(6u * (p.cols - 1) * (p.rows - 1));
        for (int j = 0; j < p.rows - 1; ++j) {
            for (int i = 0; i < p.cols - 1; ++i) {
                uint32_t a = (uint32_t)(j * p.cols + i);
                uint32_t b = a + 1;
                uint32_t c = a + p.cols;
                uint32_t d = c + 1;
                cache.push_back(a); cache.push_back(c); cache.push_back(b);
                cache.push_back(b); cache.push_back(c); cache.push_back(d);
            }
        }
        ck_cols = p.cols; ck_rows = p.rows;
    }
    out.indices = cache;
    return out;
}
} // namespace mo
