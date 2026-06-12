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
    "cascades","wave","sky","shading","foam","spray","bench"
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
    if (auto v = t["amplitude"].value<double>())      w.amplitude      = (float)*v;
}

void warn_keys(const toml::table& t, std::initializer_list<const char*> known,
               const char* table_name, LoadResult& r) {
    for (auto&& [k, _] : t) {
        std::string key{k.str()};
        bool ok = false;
        for (auto* kn : known) if (key == kn) { ok = true; break; }
        if (!ok) r.warnings.push_back(std::string("unknown key: ") + table_name + "." + key);
    }
}

float load_clamped(const toml::table& t, const char* table_name, const char* key,
                   float cur, float lo, float hi, LoadResult& r) {
    auto* node = t.get(key);
    if (!node) return cur;                       // key absent — fine
    auto v = node->value<double>();
    if (!v) {
        r.warnings.push_back(std::string(table_name) + "." + key + " has wrong type, ignored");
        return cur;
    }
    float f = (float)*v;
    if (f < lo || f > hi)
        r.warnings.push_back(std::string(table_name) + "." + key + " out of range, clamped");
    return clamp(f, lo, hi);
}

void load_shading(const toml::table& t, ShadingConfig& s, LoadResult& r) {
    warn_keys(t, {"sss_strength","sss_view_boost","sss_view_power","scatter_strength",
                  "depth_fog_density","base_thickness_m","tonemap"}, "shading", r);
    s.sss_strength      = load_clamped(t, "shading", "sss_strength",      s.sss_strength,      0.0f, 4.0f,  r);
    s.sss_view_boost    = load_clamped(t, "shading", "sss_view_boost",    s.sss_view_boost,    0.0f, 2.0f,  r);
    s.sss_view_power    = load_clamped(t, "shading", "sss_view_power",    s.sss_view_power,    1.0f, 8.0f,  r);
    s.scatter_strength  = load_clamped(t, "shading", "scatter_strength",  s.scatter_strength,  0.0f, 2.0f,  r);
    s.depth_fog_density = load_clamped(t, "shading", "depth_fog_density", s.depth_fog_density, 0.0f, 0.5f,  r);
    s.base_thickness_m  = load_clamped(t, "shading", "base_thickness_m",  s.base_thickness_m,  0.0f, 20.0f, r);
    if (auto* tn = t.get("tonemap")) {
        if (auto v = tn->value<std::string>()) {
            if      (*v == "none")     s.tonemap = Tonemap::None;
            else if (*v == "reinhard") s.tonemap = Tonemap::Reinhard;
            else if (*v == "aces")     s.tonemap = Tonemap::Aces;
            else r.warnings.push_back("unknown shading.tonemap: " + *v);
        } else {
            r.warnings.push_back("shading.tonemap has wrong type, ignored");
        }
    }
}

void load_spray(const toml::table& t, SprayConfig& s, LoadResult& r) {
    warn_keys(t, {"gain","bias","lifetime_s","wind_response","size_m","alpha","turbulence"}, "spray", r);
    s.gain          = load_clamped(t, "spray", "gain",          s.gain,          0.0f,  8.0f, r);
    s.bias          = load_clamped(t, "spray", "bias",          s.bias,          0.0f,  1.5f, r);
    s.lifetime_s    = load_clamped(t, "spray", "lifetime_s",    s.lifetime_s,    0.2f,  5.0f, r);
    s.wind_response = load_clamped(t, "spray", "wind_response", s.wind_response, 0.0f,  2.0f, r);
    s.size_m        = load_clamped(t, "spray", "size_m",        s.size_m,        0.1f,  2.0f, r);
    s.alpha         = load_clamped(t, "spray", "alpha",         s.alpha,         0.0f,  1.0f, r);
    s.turbulence    = load_clamped(t, "spray", "turbulence",    s.turbulence,    0.0f,  1.0f, r);
}

void load_foam(const toml::table& t, FoamConfig& f, LoadResult& r) {
    warn_keys(t, {"bias","gain","decay_seconds","dispersal","albedo","detail_scale","stretch","tear"}, "foam", r);
    f.bias          = load_clamped(t, "foam", "bias",          f.bias,          0.0f,  1.5f, r);
    f.gain          = load_clamped(t, "foam", "gain",          f.gain,          0.0f,  8.0f, r);
    f.decay_seconds = load_clamped(t, "foam", "decay_seconds", f.decay_seconds, 0.1f, 30.0f, r);
    f.dispersal     = load_clamped(t, "foam", "dispersal",     f.dispersal,     0.0f,  2.0f, r);
    f.albedo        = load_clamped(t, "foam", "albedo",        f.albedo,        0.0f,  1.0f, r);
    f.detail_scale  = load_clamped(t, "foam", "detail_scale",  f.detail_scale,  0.01f, 4.0f, r);
    f.stretch       = load_clamped(t, "foam", "stretch",       f.stretch,       1.0f,  4.0f, r);
    f.tear          = load_clamped(t, "foam", "tear",          f.tear,          0.0f,  1.0f, r);
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
    if (auto* s = tbl["shading"].as_table()) load_shading(*s, c.shading, r);
    if (auto* f = tbl["foam"].as_table())    load_foam(*f, c.foam, r);
    if (auto* sp = tbl["spray"].as_table())  load_spray(*sp, c.spray, r);
    // sky, cascades, bench loaders still pending; extend as needed.
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
        else if (key == "wave.amplitude")        in.config.wave.amplitude      = std::stof(val);
        else if (key == "wave.choppiness")       in.config.wave.choppiness     = std::stof(val);
        else if (key == "wave.swell")            in.config.wave.swell          = std::stof(val);
        else if (key == "cascade_count")         in.config.cascade_count = std::stoi(val);
        else if (key == "grid_cols")             in.config.grid_cols = std::stoi(val);
        else if (key == "grid_rows")             in.config.grid_rows = std::stoi(val);
        else if (key == "bench.bench_mode")      in.config.bench.bench_mode = (val == "true" || val == "1");
        else if (key == "foam.bias")          in.config.foam.bias          = std::stof(val);
        else if (key == "foam.gain")          in.config.foam.gain          = std::stof(val);
        else if (key == "foam.decay_seconds") in.config.foam.decay_seconds = std::stof(val);
        else if (key == "foam.dispersal")     in.config.foam.dispersal     = std::stof(val);
        else if (key == "foam.albedo")        in.config.foam.albedo        = std::stof(val);
        else if (key == "foam.detail_scale")  in.config.foam.detail_scale  = std::stof(val);
        else if (key == "foam.stretch")       in.config.foam.stretch       = std::stof(val);
        else if (key == "foam.tear")          in.config.foam.tear          = std::stof(val);
        else if (key == "spray.gain")         in.config.spray.gain         = std::stof(val);
        else if (key == "spray.bias")         in.config.spray.bias         = std::stof(val);
        else if (key == "spray.lifetime_s")   in.config.spray.lifetime_s   = std::stof(val);
        else if (key == "spray.wind_response") in.config.spray.wind_response = std::stof(val);
        else if (key == "spray.size_m")       in.config.spray.size_m       = std::stof(val);
        else if (key == "spray.alpha")        in.config.spray.alpha        = std::stof(val);
        else if (key == "spray.turbulence")   in.config.spray.turbulence   = std::stof(val);
        else if (key == "shading.sss_view_boost") in.config.shading.sss_view_boost = std::stof(val);
        else if (key == "shading.sss_view_power") in.config.shading.sss_view_power = std::stof(val);
        else if (key == "shading.scatter_strength") in.config.shading.scatter_strength = std::stof(val);
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
    h = fnv1a64(&c.wave.amplitude,      sizeof(c.wave.amplitude),      h);
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
    h = fnv1a64(&c.shading.sss_strength,      sizeof(c.shading.sss_strength),      h);
    h = fnv1a64(&c.shading.sss_view_boost,    sizeof(c.shading.sss_view_boost),    h);
    h = fnv1a64(&c.shading.sss_view_power,    sizeof(c.shading.sss_view_power),    h);
    h = fnv1a64(&c.shading.scatter_strength, sizeof(c.shading.scatter_strength), h);
    h = fnv1a64(&c.shading.depth_fog_density, sizeof(c.shading.depth_fog_density), h);
    h = fnv1a64(&c.shading.base_thickness_m,  sizeof(c.shading.base_thickness_m),  h);
    h = fnv1a64(&c.shading.sun_shininess,     sizeof(c.shading.sun_shininess),     h);
    h = fnv1a64(&c.shading.tonemap,           sizeof(c.shading.tonemap),           h);
    // Foam
    h = fnv1a64(&c.foam.bias,          sizeof(c.foam.bias),          h);
    h = fnv1a64(&c.foam.gain,          sizeof(c.foam.gain),          h);
    h = fnv1a64(&c.foam.decay_seconds, sizeof(c.foam.decay_seconds), h);
    h = fnv1a64(&c.foam.dispersal,     sizeof(c.foam.dispersal),     h);
    h = fnv1a64(&c.foam.albedo,        sizeof(c.foam.albedo),        h);
    h = fnv1a64(&c.foam.detail_scale,  sizeof(c.foam.detail_scale),  h);
    h = fnv1a64(&c.foam.stretch,       sizeof(c.foam.stretch),       h);
    h = fnv1a64(&c.foam.tear,          sizeof(c.foam.tear),          h);
    // Spray
    h = fnv1a64(&c.spray.gain,          sizeof(c.spray.gain),          h);
    h = fnv1a64(&c.spray.bias,          sizeof(c.spray.bias),          h);
    h = fnv1a64(&c.spray.lifetime_s,    sizeof(c.spray.lifetime_s),    h);
    h = fnv1a64(&c.spray.wind_response, sizeof(c.spray.wind_response), h);
    h = fnv1a64(&c.spray.size_m,        sizeof(c.spray.size_m),        h);
    h = fnv1a64(&c.spray.alpha,         sizeof(c.spray.alpha),         h);
    h = fnv1a64(&c.spray.turbulence,    sizeof(c.spray.turbulence),    h);
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
