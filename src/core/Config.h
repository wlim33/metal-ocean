#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>
#include <glm/glm.hpp>

namespace mo {

enum class Precision { Fp16, Fp32 };
enum class Tonemap { None, Reinhard, Aces };
enum class CameraPath { Static, Orbit, Flyby };

struct CascadeConfig {
    float size_m = 250.0f;
    int   resolution = 256;
    float normal_weight = 1.0f;
};

struct WaveConfig {
    float wind_speed_mps = 12.0f;
    float wind_dir_rad   = 0.5f;
    float choppiness     = 0.8f;
    float swell          = 0.3f;
    // Phillips spectrum amplitude. Wave height scales with sqrt(amplitude).
    float amplitude      = 4000.0f;
};

struct ShadingConfig {
    float foam_threshold = 0.15f;
    float foam_strength  = 1.0f;
    float sss_strength   = 0.5f;
    glm::vec3 sss_color  {0.1f, 0.55f, 0.45f};
    float depth_fog_density = 0.05f;
    float base_thickness_m  = 4.0f;
    glm::vec3 deep_water_color {0.01f, 0.06f, 0.10f};
    glm::vec3 extinction_rgb   {0.9f, 0.5f, 0.3f};
    float sun_shininess        = 256.0f;
    glm::vec3 sun_color        {1.4f, 1.25f, 1.0f};
    Tonemap tonemap = Tonemap::Aces;
};

struct SkyConfig {
    int cubemap_resolution = 128;
    float sun_elevation_rad = 0.7f;
    float sun_azimuth_rad   = 1.1f;
    float turbidity         = 3.0f;
};

struct BenchConfig {
    bool bench_mode = false;
    int warmup_frames = 60;
    int measure_frames = 600;
    CameraPath camera_path = CameraPath::Orbit;
    std::string output_path = "bench-{timestamp}.csv";
};

struct Config {
    int cascade_count = 3;
    // Patch sizes use coprime/irrational-ish ratios so the cascades don't
    // reinforce on a regular grid (which produces visible tile seams).
    std::array<CascadeConfig, 4> cascades {
        CascadeConfig{271.0f, 256, 1.0f},
        CascadeConfig{ 73.0f, 256, 1.0f},
        CascadeConfig{ 17.0f, 256, 1.0f},
        CascadeConfig{  3.7f, 256, 1.0f}};
    Precision spectrum_precision = Precision::Fp32;
    Precision disp_normal_precision = Precision::Fp16;

    WaveConfig wave;
    int grid_cols = 256;
    int grid_rows = 256;
    float displacement_range_m = 8.0f;

    SkyConfig sky;
    ShadingConfig shading;

    int max_in_flight_frames = 3;
    int target_fps_cap = 0;

    BenchConfig bench;
};

struct LoadResult {
    Config config;
    std::vector<std::string> warnings;
};

LoadResult load_config_from_string(const std::string& toml_text);
LoadResult load_config_from_file(const std::string& path);
LoadResult apply_overrides(LoadResult in, const std::vector<std::string>& key_value_pairs);
uint64_t   config_hash(const Config& c);
} // namespace mo
