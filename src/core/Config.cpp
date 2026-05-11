#include "core/Config.h"
#include "core/Hash.h"
#include <toml++/toml.h>
#include <sstream>
#include <fstream>
#include <algorithm>

namespace mo {
namespace {

template<typename T>
T clamp(T v, T lo, T hi) { return std::max(lo, std::min(hi, v)); }

const std::vector<std::string> KNOWN_TOP_KEYS = {
    "cascade_count","spectrum_precision","disp_normal_precision",
    "grid_cols","grid_rows","displacement_range_m",
    "max_in_flight_frames","target_fps_cap",
    "cascades","wave","sky","shading","bench"
};

void check_unknown_keys(const toml::table& t, LoadResult& r) {
    for (auto&& [k, _] : t) {
        std::string key{k.str()};
        if (std::find(KNOWN_TOP_KEYS.begin(), KNOWN_TOP_KEYS.end(), key) == KNOWN_TOP_KEYS.end())
            r.warnings.push_back("unknown top-level key: " + key);
    }
}

void load_wave(const toml::table& t, WaveConfig& w) {
    if (auto v = t["wind_speed_mps"].value<double>()) w.wind_speed_mps = (float)*v;
    if (auto v = t["wind_dir_rad"].value<double>())   w.wind_dir_rad   = (float)*v;
    if (auto v = t["choppiness"].value<double>())     w.choppiness     = (float)*v;
    if (auto v = t["swell"].value<double>())          w.swell          = (float)*v;
}

} // namespace

LoadResult load_config_from_string(const std::string& text) {
    LoadResult r;
    toml::table tbl;
    try { tbl = toml::parse(text); }
    catch (const toml::parse_error& e) {
        r.warnings.push_back(std::string("parse error: ") + e.what());
        return r;
    }
    check_unknown_keys(tbl, r);

    auto& c = r.config;
    if (auto v = tbl["cascade_count"].value<int64_t>()) {
        int n = (int)*v;
        if (n < 1 || n > 4) r.warnings.push_back("cascade_count out of [1,4], clamped");
        c.cascade_count = clamp(n, 1, 4);
    }
    if (auto v = tbl["grid_cols"].value<int64_t>()) c.grid_cols = clamp((int)*v, 32, 1024);
    if (auto v = tbl["grid_rows"].value<int64_t>()) c.grid_rows = clamp((int)*v, 32, 1024);
    if (auto v = tbl["displacement_range_m"].value<double>())
        c.displacement_range_m = clamp((float)*v, 1.0f, 30.0f);
    if (auto v = tbl["max_in_flight_frames"].value<int64_t>())
        c.max_in_flight_frames = clamp((int)*v, 1, 3);

    if (auto* w = tbl["wave"].as_table()) load_wave(*w, c.wave);
    // sky, shading, cascades, bench loaders follow the same pattern; extend as needed.
    return r;
}

LoadResult load_config_from_file(const std::string& path) {
    std::ifstream in(path);
    std::stringstream ss; ss << in.rdbuf();
    return load_config_from_string(ss.str());
}

LoadResult apply_overrides(LoadResult in, const std::vector<std::string>& kv) {
    for (auto& s : kv) {
        auto eq = s.find('=');
        if (eq == std::string::npos) { in.warnings.push_back("bad --set " + s); continue; }
        std::string key = s.substr(0, eq);
        std::string val = s.substr(eq + 1);
        if (key == "wave.wind_speed_mps")        in.config.wave.wind_speed_mps = std::stof(val);
        else if (key == "cascade_count")         in.config.cascade_count = std::stoi(val);
        else if (key == "grid_cols")             in.config.grid_cols = std::stoi(val);
        else if (key == "grid_rows")             in.config.grid_rows = std::stoi(val);
        else if (key == "bench.bench_mode")      in.config.bench.bench_mode = (val == "true" || val == "1");
        else in.warnings.push_back("unknown override key: " + key);
    }
    return in;
}

uint64_t config_hash(const Config& c) {
    uint64_t h = 0xcbf29ce484222325ull;
    // Wave
    h = fnv1a64(&c.wave.wind_speed_mps, sizeof(c.wave.wind_speed_mps), h);
    h = fnv1a64(&c.wave.wind_dir_rad,   sizeof(c.wave.wind_dir_rad),   h);
    h = fnv1a64(&c.wave.choppiness,     sizeof(c.wave.choppiness),     h);
    h = fnv1a64(&c.wave.swell,          sizeof(c.wave.swell),          h);
    // Grid / cascades
    h = fnv1a64(&c.cascade_count,       sizeof(c.cascade_count),       h);
    h = fnv1a64(&c.grid_cols,           sizeof(c.grid_cols),           h);
    h = fnv1a64(&c.grid_rows,           sizeof(c.grid_rows),           h);
    h = fnv1a64(&c.displacement_range_m,sizeof(c.displacement_range_m),h);
    for (int i = 0; i < 4; ++i) {
        h = fnv1a64(&c.cascades[i].size_m,       sizeof(float), h);
        h = fnv1a64(&c.cascades[i].resolution,   sizeof(int),   h);
        h = fnv1a64(&c.cascades[i].normal_weight,sizeof(float), h);
    }
    // Precision
    h = fnv1a64(&c.spectrum_precision,     sizeof(c.spectrum_precision),     h);
    h = fnv1a64(&c.disp_normal_precision,  sizeof(c.disp_normal_precision),  h);
    // Sky
    h = fnv1a64(&c.sky.cubemap_resolution, sizeof(c.sky.cubemap_resolution), h);
    h = fnv1a64(&c.sky.sun_elevation_rad,  sizeof(c.sky.sun_elevation_rad),  h);
    h = fnv1a64(&c.sky.sun_azimuth_rad,    sizeof(c.sky.sun_azimuth_rad),    h);
    h = fnv1a64(&c.sky.turbidity,          sizeof(c.sky.turbidity),          h);
    // Shading
    h = fnv1a64(&c.shading.foam_threshold, sizeof(c.shading.foam_threshold), h);
    h = fnv1a64(&c.shading.foam_strength,  sizeof(c.shading.foam_strength),  h);
    h = fnv1a64(&c.shading.sss_strength,   sizeof(c.shading.sss_strength),   h);
    h = fnv1a64(&c.shading.depth_fog_density, sizeof(c.shading.depth_fog_density), h);
    h = fnv1a64(&c.shading.base_thickness_m,  sizeof(c.shading.base_thickness_m),  h);
    h = fnv1a64(&c.shading.sun_shininess,     sizeof(c.shading.sun_shininess),     h);
    h = fnv1a64(&c.shading.tonemap,           sizeof(c.shading.tonemap),           h);
    // Bench (hash bench_mode + frame counts; skip output_path to avoid string pointer instability)
    h = fnv1a64(&c.bench.bench_mode,      sizeof(c.bench.bench_mode),      h);
    h = fnv1a64(&c.bench.warmup_frames,   sizeof(c.bench.warmup_frames),   h);
    h = fnv1a64(&c.bench.measure_frames,  sizeof(c.bench.measure_frames),  h);
    h = fnv1a64(&c.bench.camera_path,     sizeof(c.bench.camera_path),     h);
    // bench.output_path: hash the string content, not raw bytes
    h = fnv1a64(c.bench.output_path.data(), c.bench.output_path.size(), h);
    // Frame controls
    h = fnv1a64(&c.max_in_flight_frames,  sizeof(c.max_in_flight_frames),  h);
    h = fnv1a64(&c.target_fps_cap,        sizeof(c.target_fps_cap),        h);
    return h;
}

} // namespace mo
