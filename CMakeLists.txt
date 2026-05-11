cmake_minimum_required(VERSION 3.24)
project(metal-ocean LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB_RECURSE APP_SOURCES CONFIGURE_DEPENDS
    src/platform/*.mm src/platform/*.h
)

add_executable(metal-ocean MACOSX_BUNDLE ${APP_SOURCES})
set_target_properties(metal-ocean PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/Info.plist.in"
)
target_include_directories(metal-ocean PRIVATE src)
target_link_libraries(metal-ocean PRIVATE
    "-framework Foundation" "-framework AppKit"
    "-framework Metal" "-framework MetalKit" "-framework QuartzCore"
)
