#pragma once
#include <string>
#include <unordered_map>
namespace mo {
struct MetalContext;

struct RenderPSODesc {
    std::string vertex_fn;
    std::string fragment_fn;
    unsigned    color_pixel_format = 80; // MTLPixelFormatBGRA8Unorm_sRGB
    bool        blending = false;
};

struct PipelineCache {
    void* render_pso(const MetalContext& ctx, const RenderPSODesc& d);
    void* compute_pso(const MetalContext& ctx, const std::string& fn);

    std::unordered_map<std::string, void*> render_cache_;
    std::unordered_map<std::string, void*> compute_cache_;
};

}
