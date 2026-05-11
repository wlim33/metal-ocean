#import "platform/InputBridge.h"
namespace mo {
void InputBridge::push(const InputEvent& e) { std::lock_guard<std::mutex> g(m_); q_.push_back(e); }
std::vector<InputEvent> InputBridge::drain() {
    std::lock_guard<std::mutex> g(m_); auto r = std::move(q_); q_.clear(); return r;
}
}
