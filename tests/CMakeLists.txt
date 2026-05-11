add_executable(metal-ocean-tests
    config_test.cpp
)
target_include_directories(metal-ocean-tests PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(metal-ocean-tests PRIVATE
    gtest_main tomlplusplus::tomlplusplus glm)

# Pull in source files needed by tests (no Metal/Obj-C++)
target_sources(metal-ocean-tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src/core/Config.cpp
)

target_sources(metal-ocean-tests PRIVATE
    camera_test.cpp
    ${CMAKE_SOURCE_DIR}/src/core/OrbitCamera.cpp
)

target_sources(metal-ocean-tests PRIVATE
    projected_grid_test.cpp
    ${CMAKE_SOURCE_DIR}/src/ocean/ProjectedGrid.cpp
)

include(GoogleTest)
gtest_discover_tests(metal-ocean-tests)
