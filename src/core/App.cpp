#include "core/App.h"
namespace mo {

App::App(Config cfg) : config_(std::move(cfg)) {
    camera_.distance = 80.0f;
    camera_.pitch_rad = 0.3f;
}

void App::handle_input(InputBridge& b) {
    for (auto& e : b.drain()) {
        switch (e.kind) {
            case InputKind::MouseDown: mouse_down = true; break;
            case InputKind::MouseUp:   mouse_down = false; break;
            case InputKind::MouseMove:
                if (mouse_down) camera_.orbit(e.x, e.y);
                break;
            case InputKind::Scroll:
                camera_.zoom(e.scroll);
                break;
            case InputKind::Resize:
                if (e.height > 0) camera_.set_aspect((float)e.width / (float)e.height);
                break;
            default: break;
        }
    }
}

void App::update() { clock_.tick(); }
}
