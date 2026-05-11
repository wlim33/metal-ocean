#pragma once
#include "core/InputEvent.h"
#include <vector>
#include <mutex>
namespace mo {
class InputBridge {
public:
    void push(const InputEvent& e);
    std::vector<InputEvent> drain();
private:
    std::mutex m_;
    std::vector<InputEvent> q_;
};
}
