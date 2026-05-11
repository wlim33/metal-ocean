#include "core/Config.h"
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

} // namespace mo
