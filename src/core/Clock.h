#pragma once
namespace mo {
class Clock {
public:
    Clock();
    void   tick();
    double total_seconds() const { return t_total_; }
    double delta_seconds() const { return t_delta_; }
private:
    double t_start_ = 0;
    double t_last_ = 0;
    double t_total_ = 0;
    double t_delta_ = 0;
};
}
