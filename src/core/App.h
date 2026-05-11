#pragma once
#include "core/Config.h"
#include "core/OrbitCamera.h"
#include "core/Clock.h"
#include "platform/InputBridge.h"

namespace mo {
class App {
public:
    explicit App(Config cfg);
    void handle_input(InputBridge& b);
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
