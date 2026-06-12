#include <gtest/gtest.h>
#include <glm/glm.hpp>
#include "core/App.h"

using mo::InputEvent;
using mo::InputKind;

static InputEvent ev(InputKind k, float x = 0, float y = 0, float scroll = 0) {
    InputEvent e{};
    e.kind = k; e.x = x; e.y = y; e.scroll = scroll;
    return e;
}

// Slider drags and wheel input over the ImGui panel must not reach the
// camera: when the UI captures the mouse, MouseDown and Scroll are dropped.
TEST(AppInput, UiCaptureBlocksOrbitAndScroll) {
    mo::App app{mo::Config{}};
    glm::vec3 before = app.camera().position();

    app.handle_input({ev(InputKind::MouseDown),
                      ev(InputKind::MouseMove, 40.0f, 25.0f),
                      ev(InputKind::Scroll, 0, 0, 3.0f)},
                     /*ui_captures_mouse=*/true);

    EXPECT_FALSE(app.mouse_down) << "panel-started drag must not arm the orbit";
    glm::vec3 after = app.camera().position();
    EXPECT_FLOAT_EQ(before.x, after.x);
    EXPECT_FLOAT_EQ(before.y, after.y);
    EXPECT_FLOAT_EQ(before.z, after.z);
}

// A drag armed on the ocean keeps orbiting if the cursor crosses the panel,
// and MouseUp always lands so the drag can never get stuck.
TEST(AppInput, SceneDragSurvivesPanelCrossingAndAlwaysReleases) {
    mo::App app{mo::Config{}};

    app.handle_input({ev(InputKind::MouseDown),
                      ev(InputKind::MouseMove, 30.0f, 0.0f)},
                     /*ui_captures_mouse=*/false);
    ASSERT_TRUE(app.mouse_down);
    glm::vec3 mid = app.camera().position();

    // Cursor now over the panel mid-drag: orbit continues, release lands.
    app.handle_input({ev(InputKind::MouseMove, 30.0f, 0.0f),
                      ev(InputKind::MouseUp)},
                     /*ui_captures_mouse=*/true);

    EXPECT_FALSE(app.mouse_down);
    glm::vec3 after = app.camera().position();
    EXPECT_NE(glm::length(after - mid), 0.0f) << "mid-drag move over panel must still orbit";
}
