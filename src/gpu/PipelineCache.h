#pragma once
#include <string>
#include <unordered_map>
namespace mo {
struct MetalContext;

struct RenderPSODesc {
    std::string vertex_fn;
    std::string fragment_fn;
    unsigned    color_pixel_format = 81; // MTLPixelFormatBGRA8Unorm_sRGB (= 81)
    unsigned    depth_pixel_format = 0;  // MTLPixelFormatInvalid: no depth declared
    bool        blending = false;
};

struct PipelineCache {
    void* render_pso(const MetalContext& ctx, const RenderPSODesc& d);
    void* compute_pso(const MetalContext& ctx, const std::string& fn);

    std::unordered_map<std::string, void*> render_cache_;
    std::unordered_map<std::string, void*> compute_cache_;
};

}
