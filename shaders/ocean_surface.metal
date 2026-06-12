#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

struct OceanVertexIn { float2 xz [[attribute(0)]]; };
struct VOut {
    float4 pos       [[position]];
    float3 world_pos;
    float2 uv_xz;
    float  folding_min;
};

vertex VOut ocean_vs(
    OceanVertexIn vin                                [[stage_in]],
    constant CameraUniforms&        cam              [[buffer(1)]],
    constant OceanSurfaceUniforms&  S                [[buffer(2)]],
    array<texture2d<float>, MAX_CASCADES> disp_tex   [[texture(0)]]
) {
    constexpr sampler smp(filter::linear, address::repeat);
    float2 xz = vin.xz;
    float3 disp = float3(0.0);
    for (int i = 0; i < S.cascade_count; ++i) {
        float2 uv = xz / S.cascade_size[i];
        disp += disp_tex[i].sample(smp, uv).xyz;
    }
    VOut o;
    o.world_pos = float3(xz.x + disp.x, disp.y, xz.y + disp.z);
    o.pos = cam.view_proj * float4(o.world_pos, 1.0);
    o.uv_xz = xz;
    o.folding_min = 1.0;
    return o;
}

static float3 aces_tonemap(float3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

fragment float4 ocean_fs(
    VOut in [[stage_in]],
    constant CameraUniforms&        cam              [[buffer(1)]],
    constant OceanSurfaceUniforms&  S                [[buffer(2)]],
    array<texture2d<float>, MAX_CASCADES> normal_tex [[texture(0)]],
    texturecube<float>              sky_cube         [[texture(MAX_CASCADES)]]
) {
    constexpr sampler smp(filter::linear, mip_filter::linear, address::repeat);
    constexpr sampler cube_smp(filter::linear, address::clamp_to_edge);

    float3 n = float3(0.0, 0.0, 0.0);
    float fold_min = 1.0;
    for (int i = 0; i < S.cascade_count; ++i) {
        float2 uv = in.uv_xz / S.cascade_size[i];
        float4 nf = normal_tex[i].sample(smp, uv);
        n += nf.xyz * S.cascade_normal_weight[i];
        fold_min = min(fold_min, nf.w);
    }
    n = normalize(n + float3(0, 1e-3, 0));

    float3 V = normalize(cam.position - in.world_pos);
    float  F0 = 0.02;
    float  nv = max(dot(n, V), 0.0);
    float  F  = F0 + (1.0 - F0) * pow(1.0 - nv, 5.0);

    float3 R = reflect(-V, n);
    float3 sun = normalize(S.sun_dir);
    float3 sky_refl = sky_cube.sample(cube_smp, R).rgb;
    float  sun_spec = pow(max(dot(R, sun), 0.0), S.sun_shininess);
    float3 reflection = sky_refl + S.sun_color * sun_spec;

    float view_depth = max(0.0, -in.world_pos.y) + S.base_thickness_m;
    float3 absorb   = exp(-S.depth_fog_density * view_depth * S.extinction_rgb);
    float3 refraction = S.deep_water_color * absorb;

    float h_norm = saturate((in.world_pos.y) / S.displacement_range_m);
    float back_light = max(0.0, dot(n, -sun));
    float3 sss = S.sss_strength * h_norm * back_light * S.sss_color;

    float foam_mask = 0.0;

    float3 surface = mix(refraction, reflection, F) + sss;
    float3 final_color   = mix(surface, float3(1.0), foam_mask);

    if (S.debug_view == 1) final_color = (n * 0.5 + 0.5);
    else if (S.debug_view == 2) final_color = float3(fold_min);
    else if (S.debug_view == 3) final_color = float3(F);
    else if (S.debug_view == 4) final_color = reflection;
    else if (S.debug_view == 5) final_color = refraction;
    else if (S.debug_view == 6) final_color = sss;
    else                        final_color = aces_tonemap(final_color);

    return float4(final_color, 1.0);
}
