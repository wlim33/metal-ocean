#pragma once
namespace mo {
struct MetalContext;
class ImGuiBackend {
public:
    void init(const MetalContext& ctx, void* mtkview);
    void shutdown();
    void begin_frame(void* mtkview);
    void render(void* command_buffer, void* render_pass_desc, void* render_encoder);
    // True when ImGui wants the mouse (cursor over panel / active widget);
    // the frame loop uses it to keep panel input away from the camera.
    bool want_capture_mouse() const;
};
}
