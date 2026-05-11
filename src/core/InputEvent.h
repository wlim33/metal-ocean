#pragma once
namespace mo {

enum class InputKind { MouseMove, MouseDown, MouseUp, Scroll, KeyDown, KeyUp, Resize };

struct InputEvent {
    InputKind kind;
    float x = 0, y = 0;     // for MouseMove (delta in pixels) / cursor pos
    float scroll = 0;        // for Scroll
    int   button = 0;        // 0=left, 1=right, 2=middle
    int   key = 0;           // platform key code
    int   width = 0, height = 0; // for Resize
};
}
