#include "ui/DebugPanel.h"
#include "core/App.h"
#include "imgui.h"

namespace mo {
void draw_debug_panel(App& app) {
    auto& c = app.config();
    ImGui::SetNextWindowSize(ImVec2(380.0f, 0.0f), ImGuiCond_FirstUseEver);
    ImGui::Begin("metal-ocean");
    ImGui::Text("frame dt: %.2f ms", app.clock().delta_seconds() * 1000.0);

    if (ImGui::CollapsingHeader("Cascades", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::SliderInt("count", &c.cascade_count, 1, 4);
        for (int i = 0; i < c.cascade_count; ++i) {
            ImGui::PushID(i);
            ImGui::Text("Cascade %d", i);
            ImGui::SliderFloat("size m", &c.cascades[i].size_m, 1.0f, 500.0f);
            ImGui::SliderFloat("normal w", &c.cascades[i].normal_weight, 0.0f, 2.0f);
            ImGui::PopID();
        }
    }
    if (ImGui::CollapsingHeader("Wave")) {
        ImGui::SliderFloat("wind speed", &c.wave.wind_speed_mps, 0.0f, 30.0f);
        ImGui::SliderFloat("wind dir",   &c.wave.wind_dir_rad,  0.0f, 6.283f);
        ImGui::SliderFloat("choppiness", &c.wave.choppiness,    0.0f, 2.0f);
        ImGui::SliderFloat("swell",      &c.wave.swell,         0.0f, 1.0f);
        ImGui::SliderFloat("amplitude",  &c.wave.amplitude,     0.1f, 10000.0f, "%.2f", ImGuiSliderFlags_Logarithmic);
    }
    if (ImGui::CollapsingHeader("Sky")) {
        ImGui::SliderFloat("sun elev", &c.sky.sun_elevation_rad, 0.0f, 1.57f);
        ImGui::SliderFloat("sun azim", &c.sky.sun_azimuth_rad,  0.0f, 6.283f);
        ImGui::SliderFloat("turbidity",&c.sky.turbidity,        1.0f, 10.0f);
    }
    if (ImGui::CollapsingHeader("Shading")) {
        ImGui::SliderFloat("sss str",    &c.shading.sss_strength,   0.0f, 4.0f);
        ImGui::SliderFloat("fog density",&c.shading.depth_fog_density, 0.0f, 0.5f);
    }
    if (ImGui::CollapsingHeader("Debug view")) {
        const char* names[] = {"final","normal","folding","fresnel","reflection","refraction","sss"};
        ImGui::Combo("view", &app.debug_view, names, IM_ARRAYSIZE(names));
    }
    ImGui::End();
}
}
