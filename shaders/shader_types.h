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
    // Foam accumulation (design §3.2). decay is the per-frame multiplier
    // exp(-dt/tau), computed CPU-side in Simulation::begin_frame.
    float foam_bias;
    float foam_gain;
    float foam_decay_factor;
    float foam_dispersal;
    float inv_n;          // 1/cascade_count, for the k-share offset
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
    float foam_bias;          // eps: J level where breaking starts
    float foam_albedo;
    float foam_detail_scale;
    float sss_view_boost;
    float sss_view_power;
    float displacement_range_m;
    int   debug_view;
    float scatter_strength;
    // Wind direction (unit), for wind-aligned foam streak stretching.
    float wind_dir_x;
    float wind_dir_z;
    float foam_stretch;
    float foam_tear;
};

#define SPRAY_POOL 65536
#define SPRAY_CANDIDATES 4096

struct SprayUniforms {
    vec3  camera_pos;
    float dt;                  // CPU-clamped
    vec3  wind_vel;            // wind_dir * wind_speed * wind_response
    float gain;
    float bias;
    float lifetime_s;
    float size_m;
    float alpha;
    float annulus_inner;       // 5
    float annulus_outer;       // 150
    int   frame_index;
    int   cascade_count;
    float cascade_size[MAX_CASCADES];
    float inv_n;
    float _pad0;
    float _pad1;
    float _pad2;
};
