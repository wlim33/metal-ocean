#pragma once
#include "gpu/Buffer.h"
#include "gpu/Texture.h"
#include <cstdint>
namespace mo {
struct MetalContext;
struct PipelineCache;

struct CascadeParams {
    int   N = 256;
    float size_m = 250.0f;
    float choppiness = 0.8f;
    float wind_speed_mps = 12.0f;
    float wind_dir_rad = 0.5f;
    float amplitude = 4000.0f;
    float swell = 0.3f;
    uint32_t seed = 0xC0FFEEu;
};

class Cascade {
public:
    void init(const MetalContext& ctx, PipelineCache& cache, const CascadeParams& p);
    void rebuild_h0(const MetalContext& ctx, const CascadeParams& p);
    void encode(void* compute_encoder, float time, const CascadeParams& p);

    void* displacement_handle() const { return disp_.handle; }
    void* normal_handle()       const { return normal_.handle; }

private:
    CascadeParams params_;
    Texture h0_{}, htilde_{}, ifft_intermediate_{}, height_{};
    // Packed horizontal displacement: D̂x + i·D̂z, one complex IFFT for both.
    Texture dxdz_tilde_{}, dxdz_intermediate_{}, dxdz_field_{};
    Texture disp_{}, normal_{};
    Buffer  uniforms_{};
    void* pso_spectrum_ = nullptr;
    void* pso_fft_ = nullptr;
    void* pso_post_ = nullptr;
};
}
