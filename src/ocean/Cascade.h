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
    void encode_mipgen(void* blit_encoder);
    // Profiling split: encode() == encode_spectrum + encode_fft + encode_post.
    void encode_spectrum(void* compute_encoder, float time, const CascadeParams& p);
    void encode_fft(void* compute_encoder, const CascadeParams& p);
    void encode_post(void* compute_encoder, const CascadeParams& p);

    void* displacement_handle() const { return disp_.handle; }
    void* normal_handle()       const { return normal_.handle; }

private:
    CascadeParams params_;
    Texture h0_{};
    // h-tilde (.xy) and the Tessendorf displacement spectrum D̂x + i·D̂z (.zw)
    // share one RGBA32F texture, so each FFT pass transforms both fields in a
    // single dispatch: tilde -> ifft_intermediate -> field.
    Texture tilde_{}, ifft_intermediate_{}, field_{};
    Texture disp_{}, normal_{};
    Buffer  uniforms_{};
    void* pso_spectrum_ = nullptr;
    void* pso_fft_ = nullptr;
    void* pso_post_ = nullptr;
};
}
