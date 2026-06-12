#pragma once
#include "ocean/Cascade.h"
#include <vector>
#include <memory>
namespace mo {
struct Config;
struct MetalContext;
struct PipelineCache;

class Simulation {
public:
    void init(const MetalContext& ctx, PipelineCache& cache, const Config& cfg);
    void rebuild_if_dirty(const MetalContext& ctx, const Config& cfg);
    // Computes per-frame foam state (decay factor from real dt). Call once
    // per frame before encode/encode_stage.
    void begin_frame(float dt_seconds, const Config& cfg);
    void encode(void* compute_encoder, float time, const Config& cfg);
    void encode_mipgen(void* blit_encoder, const Config& cfg);
    // Profiling split: stage 0 = spectrum, 1 = fft, 2 = post, across all cascades.
    void encode_stage(void* compute_encoder, int stage, float time, const Config& cfg);

    int          count() const { return (int)cascades_.size(); }
    Cascade*     cascade(int i) { return cascades_[i].get(); }
    Cascade* const* data() {
        ptrs_.clear();
        for (auto& c : cascades_) ptrs_.push_back(c.get());
        return ptrs_.data();
    }
private:
    std::vector<std::unique_ptr<Cascade>> cascades_;
    std::vector<Cascade*> ptrs_;
    uint64_t cfg_hash_h0_ = 0;
    float foam_decay_factor_ = 1.0f;
};
}
