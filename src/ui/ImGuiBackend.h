#pragma once
namespace mo {
struct MetalContext;
class ImGuiBackend {
public:
    void init(const MetalContext& ctx, void* mtkview);
    void shutdown();
    void begin_frame(void* mtkview);
    void render(void* command_buffer, void* render_pass_desc, void* render_encoder);
};
}
