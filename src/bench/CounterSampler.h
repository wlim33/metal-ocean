#pragma once
#include <vector>
#include <string>
namespace mo {
struct MetalContext;

struct PassTiming {
    std::string name;
    double      ms = 0.0;
};

class CounterSampler {
public:
    bool init(const MetalContext& ctx);
    bool supported() const { return supported_; }
    void* sample_buffer() const { return buffer_; }
    void resolve(int sample_count, std::vector<PassTiming>& out_named, const std::vector<std::string>& names);

    int next_index = 0;
    static constexpr int CAPACITY = 32;
private:
    bool  supported_ = false;
    void* buffer_ = nullptr; // id<MTLCounterSampleBuffer>
    void* counter_set_ = nullptr;
};
}
