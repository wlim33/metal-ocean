#pragma once
#include "gpu/Texture.h"
#include <cstdint>
namespace mo {
struct MetalContext;
struct PipelineCache;
class  OrbitCamera;
struct Config;

class SkyRenderer {
public:
    void init(const MetalContext& ctx, PipelineCache& cache);
    void encode_full_screen(void* encoder, const OrbitCamera& cam, const Config& cfg);
    void bake_cubemap_if_dirty(const MetalContext& ctx, void* command_buffer, const Config& cfg);
    void* cubemap_handle() const { return cubemap_.handle; }

private:
    void create_cubemap(const MetalContext& ctx, int size);
    void* pso_ = nullptr;
    void* pso_cube_ = nullptr;
    Texture cubemap_{};
    uint64_t last_config_hash_ = 0;
};
}
