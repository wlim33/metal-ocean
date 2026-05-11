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
