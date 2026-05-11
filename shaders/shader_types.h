#pragma once
#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#define ALIGN(x)
#else
#include <simd/simd.h>
#define ALIGN(x) alignas(x)
#endif

struct CameraUniforms {
    simd_float4x4 view;
    simd_float4x4 proj;
    simd_float4x4 view_proj;
    simd_float3   position;
    float         _pad;
};
