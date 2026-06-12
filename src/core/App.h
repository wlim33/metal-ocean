#pragma once
#include "core/Config.h"
#include "core/OrbitCamera.h"
#include "core/Clock.h"
#include "core/InputEvent.h"
#include <vector>

namespace mo {
class App {
public:
    explicit App(Config cfg);
    // ui_captures_mouse (ImGui WantCaptureMouse): MouseDown and Scroll are
    // dropped so panel interaction never drives the camera; MouseUp always
    // lands so an ocean-started drag can cross the panel and still release.
    void handle_input(const std::vector<InputEvent>& events, bool ui_captures_mouse);
    void update();

    const OrbitCamera& camera() const { return camera_; }
    OrbitCamera&       camera()       { return camera_; }
    const Config&      config() const { return config_; }
    Config&            config()       { return config_; }
    const Clock&       clock()  const { return clock_; }

    bool mouse_down = false;
    int  debug_view = 0;
private:
    Config config_;
    OrbitCamera camera_;
    Clock clock_;
};
}
