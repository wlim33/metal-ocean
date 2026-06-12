#include <metal_stdlib>
#include "shader_types.h"
#include "foam_common.h"
using namespace metal;

struct OceanVertexIn { float2 xz [[attribute(0)]]; };
struct VOut {
    float4 pos       [[position]];
    float3 world_pos;
    float2 uv_xz;
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
    texturecube<float>              sky_cube         [[texture(MAX_CASCADES)]],
    array<texture2d<float>, MAX_CASCADES> foam_tex   [[texture(MAX_CASCADES + 1)]],
    texture2d<float>                foam_detail      [[texture(2 * MAX_CASCADES + 1)]]
) {
    constexpr sampler smp(filter::linear, mip_filter::linear, address::repeat);
    constexpr sampler cube_smp(filter::linear, address::clamp_to_edge);
    constexpr sampler cube_smp_mip(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float3 n = float3(0.0, 0.0, 0.0);
    float fold_min = 1.0;                       // kept for debug_view == 2
    float mu = 0.0, m2 = 0.0, mu_sq = 0.0, P = 0.0;
    for (int i = 0; i < S.cascade_count; ++i) {
        float2 uv = in.uv_xz / S.cascade_size[i];
        float4 nf = normal_tex[i].sample(smp, uv);
        n += nf.xyz * S.cascade_normal_weight[i];
        fold_min = min(fold_min, nf.w);
        float4 f = foam_tex[i].sample(smp, uv);
        mu    += f.x;                           // D&B: moments sum unweighted
        m2    += f.y;
        mu_sq += f.x * f.x;
        P     += S.cascade_normal_weight[i] * f.z;
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

    // SSS with view-through crest term (design §4.3)
    float h_norm = saturate((in.world_pos.y) / S.displacement_range_m);
    float back_light = max(0.0, dot(n, -sun));
    float view_through = S.sss_view_boost * pow(max(dot(-V, sun), 0.0), S.sss_view_power);
    float3 sss = S.sss_strength * h_norm * (back_light + view_through) * S.sss_color;

    // Whitecap coverage (design §4.1): instantaneous anti-aliased W from
    // mip-filtered k moments, max'd with the persistent buffer P, eroded by
    // the two-scale detail texture (applied once, here only).
    float sigma2 = max(0.0, m2 - mu_sq);
    float W = foamc_coverage(S.foam_bias, mu, sigma2);
    P = saturate(P);
    float d_hi = foam_detail.sample(smp, in.uv_xz * S.foam_detail_scale).r;
    float d_lo = foam_detail.sample(smp, in.uv_xz * S.foam_detail_scale * 0.25).r;
    float detail = mix(d_lo * 0.7, d_hi * 1.3, P);
    float foam_mask = saturate(max(W, P) * detail);

    // Foam material (design §4.2): Lambertian layer, kills the mirror term.
    // Sun term is irradiance·(N·L)/π (proper Lambertian); the mip-3 cube
    // sample is a radiance-average ambient proxy left un-normalized on
    // purpose — its weight is absorbed into foam_albedo at tuning time.
    float3 ambient_sky = sky_cube.sample(cube_smp_mip, n, level(3.0)).rgb;
    float3 foam_lit = S.foam_albedo * (ambient_sky + S.sun_color * max(dot(n, sun), 0.0) * (1.0 / M_PI_F));
    F *= (1.0 - foam_mask);

    float3 surface = mix(refraction, reflection, F) + sss;
    float3 final_color = mix(surface, foam_lit, foam_mask);

    if (S.debug_view == 1) final_color = (n * 0.5 + 0.5);
    else if (S.debug_view == 2) final_color = float3(fold_min);
    else if (S.debug_view == 3) final_color = float3(F);
    else if (S.debug_view == 4) final_color = reflection;
    else if (S.debug_view == 5) final_color = refraction;
    else if (S.debug_view == 6) final_color = sss;
    else if (S.debug_view == 7) final_color = float3(W);
    else if (S.debug_view == 8) final_color = float3(P);
    else if (S.debug_view == 9) final_color = float3(foam_mask);
    else if (S.debug_view == 10) final_color = float3(detail);
    else                        final_color = aces_tonemap(final_color);

    return float4(final_color, 1.0);
}
