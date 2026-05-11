#include "core/Clock.h"
#include <chrono>
namespace mo {
static double now_s() {
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
}
Clock::Clock() { t_start_ = t_last_ = now_s(); }
void Clock::tick() {
    double n = now_s();
    t_delta_ = n - t_last_;
    t_total_ = n - t_start_;
    t_last_  = n;
}
}
