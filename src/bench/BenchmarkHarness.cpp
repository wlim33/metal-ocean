#include "bench/BenchmarkHarness.h"
#include <chrono>
#include <sstream>
#include <iomanip>
namespace mo {

static std::string substitute_timestamp(std::string path) {
    auto pos = path.find("{timestamp}");
    if (pos == std::string::npos) return path;
    auto t = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::ostringstream ts; std::tm tm{};
#if defined(_WIN32)
    localtime_s(&tm, &t);
#else
    localtime_r(&t, &tm);
#endif
    ts << std::put_time(&tm, "%Y%m%d-%H%M%S");
    return path.substr(0, pos) + ts.str() + path.substr(pos + 11);
}

void BenchmarkHarness::start(const Config& cfg, uint64_t cfg_hash) {
    if (!cfg.bench.bench_mode) return;
    active_ = true;
    warmup_ = cfg.bench.warmup_frames;
    measure_ = cfg.bench.measure_frames;
    hash_ = cfg_hash;
    out_.open(substitute_timestamp(cfg.bench.output_path));
    out_ << "frame_idx,cpu_ms,gpu_total_ms,drawable_wait_ms,config_hash\n";
}

void BenchmarkHarness::record(const FrameTiming& t) {
    if (!active_) return;
    if (frame_idx_ >= warmup_) {
        out_ << t.frame_idx << ',' << t.cpu_ms << ',' << t.gpu_total_ms
             << ',' << t.drawable_wait_ms << ',' << hash_ << '\n';
        // Termination races the tail of the completed-handler queue; flush so
        // a buffered partial batch isn't lost when the app exits.
        out_.flush();
    }
    ++frame_idx_;
}

bool BenchmarkHarness::should_exit() const {
    return active_ && frame_idx_ >= warmup_ + measure_;
}
}
