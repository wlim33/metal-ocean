#include <gtest/gtest.h>
#include "core/Config.h"

TEST(Config, DefaultsLoadFromEmptyToml) {
    auto result = mo::load_config_from_string("");
    EXPECT_EQ(result.config.cascade_count, 3);
    EXPECT_EQ(result.config.cascades[0].resolution, 256);
    EXPECT_FLOAT_EQ(result.config.wave.wind_speed_mps, 12.0f);
    EXPECT_TRUE(result.warnings.empty());
}

TEST(Config, OverridesWindSpeed) {
    auto result = mo::load_config_from_string("[wave]\nwind_speed_mps = 20.0\n");
    EXPECT_FLOAT_EQ(result.config.wave.wind_speed_mps, 20.0f);
}

TEST(Config, ClampsCascadeCount) {
    auto result = mo::load_config_from_string("cascade_count = 9\n");
    EXPECT_LE(result.config.cascade_count, 4);
    EXPECT_GE(result.config.cascade_count, 1);
    EXPECT_FALSE(result.warnings.empty());
}

TEST(Config, RejectsUnknownTopLevelKey) {
    auto result = mo::load_config_from_string("zorp = 1\n");
    bool has_unknown = false;
    for (auto& w : result.warnings) if (w.find("zorp") != std::string::npos) has_unknown = true;
    EXPECT_TRUE(has_unknown);
}

TEST(Config, CliOverrideAppliesAfterToml) {
    auto base = mo::load_config_from_string("[wave]\nwind_speed_mps = 5.0\n");
    auto r = mo::apply_overrides(std::move(base), {"wave.wind_speed_mps=18.0"});
    EXPECT_FLOAT_EQ(r.config.wave.wind_speed_mps, 18.0f);
}

TEST(Config, HashStableForIdenticalConfigs) {
    auto a = mo::load_config_from_string("");
    auto b = mo::load_config_from_string("");
    EXPECT_EQ(mo::config_hash(a.config), mo::config_hash(b.config));
}

TEST(Config, HashChangesWithDifferentConfig) {
    auto a = mo::load_config_from_string("");
    auto b = mo::load_config_from_string("[wave]\nwind_speed_mps = 20.0\n");
    EXPECT_NE(mo::config_hash(a.config), mo::config_hash(b.config));
}

TEST(Config, FoamTableRoundTrip) {
    auto r = mo::load_config_from_string(R"(
[foam]
bias = 0.9
gain = 2.0
decay_seconds = 6.5
dispersal = 1.2
albedo = 0.45
detail_scale = 0.5
)");
    EXPECT_TRUE(r.warnings.empty());
    EXPECT_FLOAT_EQ(r.config.foam.bias, 0.9f);
    EXPECT_FLOAT_EQ(r.config.foam.gain, 2.0f);
    EXPECT_FLOAT_EQ(r.config.foam.decay_seconds, 6.5f);
    EXPECT_FLOAT_EQ(r.config.foam.dispersal, 1.2f);
    EXPECT_FLOAT_EQ(r.config.foam.albedo, 0.45f);
    EXPECT_FLOAT_EQ(r.config.foam.detail_scale, 0.5f);
}

TEST(Config, FoamValuesClampWithWarning) {
    auto r = mo::load_config_from_string("[foam]\nbias = 9.0\n");
    EXPECT_FLOAT_EQ(r.config.foam.bias, 1.5f);
    ASSERT_EQ(r.warnings.size(), 1u);
    EXPECT_NE(r.warnings[0].find("foam.bias"), std::string::npos);
}

TEST(Config, ShadingTableNowLoads) {
    auto r = mo::load_config_from_string(R"(
[shading]
sss_strength = 1.25
sss_view_boost = 0.9
sss_view_power = 5.0
depth_fog_density = 0.1
base_thickness_m = 2.0
tonemap = "reinhard"
)");
    EXPECT_TRUE(r.warnings.empty());
    EXPECT_FLOAT_EQ(r.config.shading.sss_strength, 1.25f);
    EXPECT_FLOAT_EQ(r.config.shading.sss_view_boost, 0.9f);
    EXPECT_FLOAT_EQ(r.config.shading.sss_view_power, 5.0f);
    EXPECT_FLOAT_EQ(r.config.shading.depth_fog_density, 0.1f);
    EXPECT_FLOAT_EQ(r.config.shading.base_thickness_m, 2.0f);
    EXPECT_EQ(r.config.shading.tonemap, mo::Tonemap::Reinhard);
}

TEST(Config, RemovedFoamKeysWarnLoudly) {
    auto r = mo::load_config_from_string("[shading]\nfoam_threshold = 0.4\n");
    ASSERT_FALSE(r.warnings.empty());
    EXPECT_NE(r.warnings[0].find("foam_threshold"), std::string::npos);
}

TEST(Config, FoamOverrides) {
    mo::LoadResult base;
    auto r = mo::apply_overrides(std::move(base), {"foam.bias=0.7", "foam.decay_seconds=2"});
    EXPECT_FLOAT_EQ(r.config.foam.bias, 0.7f);
    EXPECT_FLOAT_EQ(r.config.foam.decay_seconds, 2.0f);
    EXPECT_TRUE(r.warnings.empty());
}

TEST(Config, HashSensitiveToEveryFoamKey) {
    mo::Config a;
    uint64_t h0 = mo::config_hash(a);
    auto flip = [&](auto setter) { mo::Config c; setter(c); EXPECT_NE(mo::config_hash(c), h0); };
    flip([](mo::Config& c) { c.foam.bias = 0.5f; });
    flip([](mo::Config& c) { c.foam.gain = 3.0f; });
    flip([](mo::Config& c) { c.foam.decay_seconds = 1.0f; });
    flip([](mo::Config& c) { c.foam.dispersal = 0.0f; });
    flip([](mo::Config& c) { c.foam.albedo = 0.9f; });
    flip([](mo::Config& c) { c.foam.detail_scale = 1.0f; });
    flip([](mo::Config& c) { c.shading.sss_view_boost = 1.5f; });
    flip([](mo::Config& c) { c.shading.sss_view_power = 7.0f; });
}

TEST(Config, NewDefaults) {
    mo::Config c;
    EXPECT_FLOAT_EQ(c.wave.choppiness, 1.15f);
    EXPECT_FLOAT_EQ(c.foam.bias, 0.85f);
}
