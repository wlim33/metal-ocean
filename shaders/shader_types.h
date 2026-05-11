#pragma once
#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#define ALIGN(x)
typedef float4x4 mat4;
typedef float3   vec3;
#else
#include <simd/simd.h>
#define ALIGN(x) alignas(x)
typedef simd_float4x4 mat4;
typedef simd_float3   vec3;
#endif

struct CameraUniforms {
    mat4  view;
    mat4  proj;
    mat4  view_proj;
    vec3  position;
    float _pad;
};

struct SkyUniforms {
    mat4  inv_view_proj;
    vec3  sun_dir;
    float turbidity;
    vec3  camera_pos;
    float _pad;
};

struct CascadeUniforms {
    int   N;
    float L;
    float t;
    float choppiness;
};

struct FftPassUniforms {
    int N;
    int direction; // 0 = horizontal, 1 = vertical
};

#define MAX_CASCADES 4

struct OceanSurfaceUniforms {
    int   cascade_count;
    float cascade_size[MAX_CASCADES];
    float cascade_normal_weight[MAX_CASCADES];
    vec3  sun_dir;
    float _pad0;
    vec3  sun_color;
    float sun_shininess;
    vec3  deep_water_color;
    float depth_fog_density;
    vec3  extinction_rgb;
    float base_thickness_m;
    vec3  sss_color;
    float sss_strength;
    float foam_threshold;
    float foam_strength;
    float displacement_range_m;
    int   debug_view;
};
