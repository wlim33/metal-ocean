#pragma once
#include "gpu/Buffer.h"
#include <cstddef>

namespace mo {
struct MetalContext;
struct PipelineCache;
class  OrbitCamera;
struct ProjectedGridOutput;

class OceanRenderer {
public:
    void init(const MetalContext& ctx, PipelineCache& cache);
    void upload_grid(const MetalContext& ctx, const ProjectedGridOutput& grid, int frame_index);
    void encode_wireframe(void* encoder, const OrbitCamera& cam, int frame_index);

    static constexpr int RING = 3;
private:
    Buffer vbo_[RING]{};
    Buffer ibo_[RING]{};
    size_t index_count_[RING]{};
    Buffer cam_buf_[RING]{};
    void*  pso_wire_ = nullptr;
};
}
