#import "ocean/Simulation.h"
#import "core/Config.h"
#import "core/Hash.h"
#import "gpu/MetalContext.h"
#import "gpu/PipelineCache.h"

namespace mo {

static CascadeParams make_params(const Config& cfg, int i) {
    CascadeParams p;
    p.N = cfg.cascades[i].resolution;
    p.size_m = cfg.cascades[i].size_m;
    p.wind_speed_mps = cfg.wave.wind_speed_mps;
    p.wind_dir_rad   = cfg.wave.wind_dir_rad;
    p.choppiness     = cfg.wave.choppiness;
    p.amplitude      = cfg.wave.amplitude;
    p.swell          = cfg.wave.swell;
    p.seed = 0xC0FFEEu ^ (uint32_t)(i * 0x9E3779B9u);
    return p;
}

// Hash of everything that feeds h0 generation; a change triggers rebuild_h0.
static uint64_t h0_config_hash(const Config& cfg) {
    struct H {
        int n; float size[4]; float wind; float dir; float amp; float swell;
        uint32_t seed;
    } h{};
    h.n = cfg.cascade_count;
    for (int i = 0; i < cfg.cascade_count; ++i) h.size[i] = cfg.cascades[i].size_m;
    h.wind  = cfg.wave.wind_speed_mps;
    h.dir   = cfg.wave.wind_dir_rad;
    h.amp   = cfg.wave.amplitude;
    h.swell = cfg.wave.swell;
    h.seed  = 0xC0FFEE;
    return fnv1a64(&h, sizeof(h));
}

void Simulation::init(const MetalContext& ctx, PipelineCache& cache, const Config& cfg) {
    cascades_.clear();
    for (int i = 0; i < cfg.cascade_count; ++i) {
        auto c = std::make_unique<Cascade>();
        c->init(ctx, cache, make_params(cfg, i));
        cascades_.push_back(std::move(c));
    }
    cfg_hash_h0_ = h0_config_hash(cfg);
}

void Simulation::rebuild_if_dirty(const MetalContext& ctx, const Config& cfg) {
    uint64_t nh = h0_config_hash(cfg);
    if (nh == cfg_hash_h0_ && (int)cascades_.size() == cfg.cascade_count) return;

    // Only rebuild h0 for existing cascades; for cascade-count growth/shrink, we'd need
    // to re-init with the PipelineCache (kept simple here — resize-down only).
    for (int i = 0; i < (int)cascades_.size() && i < cfg.cascade_count; ++i) {
        cascades_[i]->rebuild_h0(ctx, make_params(cfg, i));
    }
    cfg_hash_h0_ = nh;
}

void Simulation::encode(void* enc, float time, const Config& cfg) {
    for (int i = 0; i < (int)cascades_.size() && i < cfg.cascade_count; ++i) {
        cascades_[i]->encode(enc, time, make_params(cfg, i));
    }
}
}
