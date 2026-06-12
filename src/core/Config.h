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
    float choppiness     = 1.35f;
    float swell          = 0.55f;
    // Phillips spectrum amplitude. Wave height scales with sqrt(amplitude).
    float amplitude      = 7000.0f;
};

struct ShadingConfig {
    float sss_strength   = 0.5f;
    float sss_view_boost = 0.6f;   // view-through crest SSS (design §4.3)
    float sss_view_power = 3.0f;
    // Broad subsurface scatter: blends deep_water_color toward sss_color
    // across wave faces (grazing view + peaks + sunward) — the "clear water"
    // term; SoT-style, kept physically moderate at 0.9.
    float scatter_strength = 0.9f;
    glm::vec3 sss_color  {0.1f, 0.55f, 0.45f};
    float depth_fog_density = 0.05f;
    float base_thickness_m  = 4.0f;
    glm::vec3 deep_water_color {0.01f, 0.06f, 0.10f};
    glm::vec3 extinction_rgb   {0.9f, 0.5f, 0.3f};
    float sun_shininess        = 256.0f;
    glm::vec3 sun_color        {1.4f, 1.25f, 1.0f};
    Tonemap tonemap = Tonemap::Aces;
};

// Whitecap foam (design §3, §7). bias = J level where breaking starts.
struct FoamConfig {
    float bias          = 0.75f;
    float gain          = 1.5f;
    float decay_seconds = 3.0f;
    float dispersal     = 0.7f;   // blur radius, texels; 0 = off
    float albedo        = 0.55f;
    float detail_scale  = 0.35f;
    float stretch       = 1.6f;   // along-wind streak elongation, 1 = isotropic
    float tear          = 0.8f;   // 0 = soft multiply edges, 1 = fully torn
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
    int cascade_count = 2;
    // Patch sizes use coprime/irrational-ish ratios so the cascades don't
    // reinforce on a regular grid (which produces visible tile seams).
    std::array<CascadeConfig, 4> cascades {
        CascadeConfig{419.0f, 256, 0.65f},
        CascadeConfig{ 97.0f, 256, 0.35f},
        CascadeConfig{ 17.0f, 256, 1.0f},
        CascadeConfig{  3.7f, 256, 1.0f}};
    Precision spectrum_precision = Precision::Fp32;
    Precision disp_normal_precision = Precision::Fp16;

    WaveConfig wave;
    int grid_cols = 256;
    int grid_rows = 256;
    float displacement_range_m = 12.0f;

    SkyConfig sky;
    ShadingConfig shading;
    FoamConfig foam;

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
