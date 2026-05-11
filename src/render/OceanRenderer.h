#pragma once
#include "gpu/Buffer.h"
#include <cstddef>
namespace mo {
struct MetalContext;
struct PipelineCache;
class  OrbitCamera;
struct ProjectedGridOutput;
struct Config;
class  Cascade;
class  SkyRenderer;

class OceanRenderer {
public:
    void init(const MetalContext& ctx, PipelineCache& cache);
    void upload_grid(const MetalContext& ctx, const ProjectedGridOutput& grid, int frame_index);
    void encode(void* encoder, const OrbitCamera& cam, const Config& cfg,
                Cascade* const* cascades, int cascade_count,
                const SkyRenderer& sky, int frame_index, int debug_view);

    static constexpr int RING = 3;
private:
    Buffer vbo_[RING]{}, ibo_[RING]{}, cam_buf_[RING]{}, surf_buf_[RING]{};
    size_t index_count_[RING]{};
    void*  pso_ = nullptr;
};
}
