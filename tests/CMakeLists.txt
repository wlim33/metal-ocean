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

target_sources(metal-ocean-tests PRIVATE
    fft_reference_test.cpp
    support/cpu_fft_reference.cpp
)
target_include_directories(metal-ocean-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# GPU/CPU parity: executes the butterfly schedule shared with shaders/fft.metal.
target_sources(metal-ocean-tests PRIVATE fft_parity_test.cpp)
target_include_directories(metal-ocean-tests PRIVATE ${CMAKE_SOURCE_DIR}/shaders)

# Foam math parity: executes the formulas shared with shaders/foam_update.metal
# and shaders/ocean_surface.metal.
target_sources(metal-ocean-tests PRIVATE foam_test.cpp)

target_sources(metal-ocean-tests PRIVATE
    spectrum_test.cpp
    ${CMAKE_SOURCE_DIR}/src/ocean/Spectrum.cpp
)

include(GoogleTest)
gtest_discover_tests(metal-ocean-tests)
