#import "ui/ImGuiBackend.h"
#import "gpu/MetalContext.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

namespace mo {

void ImGuiBackend::init(const MetalContext& ctx, void* mtkview) {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::StyleColorsDark();
    ImGui_ImplMetal_Init((__bridge id<MTLDevice>)ctx.device);
    MTKView* v = (__bridge MTKView*)mtkview;
    ImGui_ImplOSX_Init(v);
}
void ImGuiBackend::shutdown() {
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplOSX_Shutdown();
    ImGui::DestroyContext();
}
void ImGuiBackend::begin_frame(void* mtkview) {
    MTKView* v = (__bridge MTKView*)mtkview;
    ImGui_ImplMetal_NewFrame(v.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(v);
    ImGui::NewFrame();
}
bool ImGuiBackend::want_capture_mouse() const {
    return ImGui::GetCurrentContext() && ImGui::GetIO().WantCaptureMouse;
}
void ImGuiBackend::render(void* command_buffer, void*, void* render_encoder) {
    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),
        (__bridge id<MTLCommandBuffer>)command_buffer,
        (__bridge id<MTLRenderCommandEncoder>)render_encoder);
}
}
