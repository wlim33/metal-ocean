cmake_minimum_required(VERSION 3.24)
project(metal-ocean LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

file(GLOB_RECURSE APP_SOURCES CONFIGURE_DEPENDS
    src/*.mm src/*.cpp src/*.h)
list(FILTER APP_SOURCES EXCLUDE REGEX ".*/tests/.*")

add_executable(metal-ocean MACOSX_BUNDLE ${APP_SOURCES})
set_source_files_properties(
    src/platform/AppDelegate.mm
    src/platform/OceanView.mm
    src/platform/InputBridge.mm
    src/gpu/MetalContext.mm
    src/gpu/PipelineCache.mm
    src/gpu/Buffer.mm
    src/gpu/Texture.mm
    src/ui/ImGuiBackend.mm
    src/render/OceanRenderer.mm
    src/render/SkyRenderer.mm
    src/render/SprayRenderer.mm
    src/ocean/Cascade.mm
    src/ocean/Simulation.mm
    src/bench/CounterSampler.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc")
set_target_properties(metal-ocean PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/Info.plist.in"
)
target_include_directories(metal-ocean PRIVATE src ${CMAKE_SOURCE_DIR}/shaders)
target_link_libraries(metal-ocean PRIVATE
    "-framework Foundation" "-framework AppKit"
    "-framework Metal" "-framework MetalKit" "-framework QuartzCore"
)

include(FetchContent)

FetchContent_Declare(glm
    GIT_REPOSITORY https://github.com/g-truc/glm.git
    GIT_TAG 1.0.1
    GIT_SHALLOW TRUE)

FetchContent_Declare(tomlplusplus
    GIT_REPOSITORY https://github.com/marzer/tomlplusplus.git
    GIT_TAG v3.4.0
    GIT_SHALLOW TRUE)

FetchContent_Declare(imgui
    GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG docking
    GIT_SHALLOW TRUE)

FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
    GIT_SHALLOW TRUE)

set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(glm tomlplusplus imgui googletest)

add_library(imgui STATIC
    ${imgui_SOURCE_DIR}/imgui.cpp
    ${imgui_SOURCE_DIR}/imgui_demo.cpp
    ${imgui_SOURCE_DIR}/imgui_draw.cpp
    ${imgui_SOURCE_DIR}/imgui_tables.cpp
    ${imgui_SOURCE_DIR}/imgui_widgets.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_metal.mm
    ${imgui_SOURCE_DIR}/backends/imgui_impl_osx.mm
)
target_include_directories(imgui PUBLIC ${imgui_SOURCE_DIR} ${imgui_SOURCE_DIR}/backends)
target_link_libraries(imgui PUBLIC
    "-framework Metal" "-framework MetalKit"
    "-framework AppKit" "-framework GameController")

target_link_libraries(metal-ocean PRIVATE glm tomlplusplus::tomlplusplus imgui)

file(GLOB METAL_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/shaders/*.metal")
set(AIR_FILES)
foreach(METAL_SRC ${METAL_SOURCES})
    get_filename_component(NAME_WE ${METAL_SRC} NAME_WE)
    set(AIR_OUT ${CMAKE_BINARY_DIR}/air/${NAME_WE}.air)
    add_custom_command(OUTPUT ${AIR_OUT}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/air
        COMMAND xcrun -sdk macosx metal -std=metal3.0 -O3 -I ${CMAKE_SOURCE_DIR}/shaders
                -c ${METAL_SRC} -o ${AIR_OUT}
        DEPENDS ${METAL_SRC} ${CMAKE_SOURCE_DIR}/shaders/shader_types.h
                ${CMAKE_SOURCE_DIR}/shaders/fft_common.h
                ${CMAKE_SOURCE_DIR}/shaders/foam_common.h
                ${CMAKE_SOURCE_DIR}/shaders/spray_common.h
        VERBATIM)
    list(APPEND AIR_FILES ${AIR_OUT})
endforeach()

set(METALLIB ${CMAKE_BINARY_DIR}/default.metallib)
add_custom_command(OUTPUT ${METALLIB}
    COMMAND xcrun -sdk macosx metallib ${AIR_FILES} -o ${METALLIB}
    DEPENDS ${AIR_FILES} VERBATIM)
add_custom_target(shaders DEPENDS ${METALLIB})
add_dependencies(metal-ocean shaders)

# Bundle resources are dependency-tracked copies, NOT POST_BUILD hooks:
# POST_BUILD only fires when the executable relinks, so shader-only or
# config-only edits would leave a stale copy inside the bundle.
add_custom_target(bundle_resources ALL
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${METALLIB}
            $<TARGET_BUNDLE_CONTENT_DIR:metal-ocean>/Resources/default.metallib
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_SOURCE_DIR}/default-config.toml
            $<TARGET_BUNDLE_CONTENT_DIR:metal-ocean>/Resources/default-config.toml
    DEPENDS ${METALLIB} metal-ocean
    VERBATIM)

enable_testing()
add_subdirectory(tests)

add_custom_target(run
    COMMAND open ${CMAKE_BINARY_DIR}/metal-ocean.app
    DEPENDS metal-ocean)
