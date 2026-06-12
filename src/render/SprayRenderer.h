#pragma once
#include "gpu/Buffer.h"
namespace mo {
struct MetalContext;
struct PipelineCache;
struct Config;
class  OrbitCamera;
class  Cascade;

class SprayRenderer {
public:
    void init(const MetalContext& ctx, PipelineCache& cache);
    // Appended to the existing per-frame compute encoder, after the sim.
    void encode_compute(void* compute_encoder, int frame_index, float dt,
                        const Config& cfg, const OrbitCamera& cam,
                        Cascade* const* cascades, int cascade_count);
    // After the ocean draw, before ImGui. Tests depth, writes none.
    void encode_draw(void* render_encoder, int frame_index, const OrbitCamera& cam, const Config& cfg);
    // Zeroes the per-frame alive counter (4 bytes at offset 4).
    // The ring head at offset 0 persists across frames by design.
    void encode_counter_reset(void* blit_encoder);

private:
    static constexpr int RING = 3;
    Buffer particles_{}, counters_{}, instances_{}, indirect_{}, quad_ibo_{};
    Buffer uniforms_[3]{};      // SprayUniforms ring (CPU-written per frame)
    Buffer cam_buf_[3]{};       // CameraUniforms ring for the draw
    void* pso_emit_ = nullptr;
    void* pso_update_ = nullptr;
    void* pso_finalize_ = nullptr;
    void* pso_draw_ = nullptr;     // billboard draw PSO
    void* depth_state_ = nullptr;  // test LessEqual, write OFF
};
}
