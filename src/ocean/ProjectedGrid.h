#pragma once
#include <glm/glm.hpp>
#include <vector>

namespace mo {

struct ProjectedGridParams {
    int   cols = 256;
    int   rows = 256;
    float sea_level = 0.0f;
    float displacement_range_m = 8.0f;
};

struct ProjectedGridOutput {
    std::vector<glm::vec2> vertices_xz; // size = cols * rows; sea-plane (x, z)
    std::vector<uint32_t>  indices;     // size = 6 * (cols-1) * (rows-1); CCW triangles
    bool visible = true;
};

// `view`, `proj` come from the main camera. The function constructs a "displacement camera"
// internally (lifted out of the wave slab if needed) and returns world-space (x,z) per vertex.
ProjectedGridOutput build_projected_grid(const glm::mat4& view,
                                         const glm::mat4& proj,
                                         const glm::vec3& camera_pos,
                                         const ProjectedGridParams& p);
}
