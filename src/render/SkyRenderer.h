#pragma once
namespace mo {
struct MetalContext;
struct PipelineCache;
class  OrbitCamera;
struct Config;

class SkyRenderer {
public:
    void init(const MetalContext& ctx, PipelineCache& cache);
    void encode_full_screen(void* encoder, const OrbitCamera& cam, const Config& cfg);
private:
    void* pso_ = nullptr;
};
}
