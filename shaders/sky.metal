#include <metal_stdlib>
#include "shader_types.h"
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };

static VOut sky_vs_impl(uint vid) {
    const float2 verts[3] = { float2(-1,-3), float2(-1, 1), float2( 3, 1) };
    VOut o;
    o.pos = float4(verts[vid], 0, 1);
    o.uv  = verts[vid];
    return o;
}

vertex VOut sky_vs(uint vid [[vertex_id]]) {
    return sky_vs_impl(vid);
}

// Preetham sky (slightly simplified). Returns linear RGB radiance.
static float3 preetham(float3 view_dir, float3 sun_dir, float T) {
    float cos_theta = max(view_dir.y, 0.001);
    float cos_gamma = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
    float gamma = acos(cos_gamma);

    // Perez coefficients (Y) approximated for sky luminance
    float A = -0.0193 * T - 0.2592;
    float B = -0.0665 * T + 0.0008;
    float C = -0.0004 * T + 0.2125;
    float D = -0.0641 * T - 0.8989;
    float E = -0.0033 * T + 0.0452;

    float F  = (1.0 + A * exp(B / cos_theta)) * (1.0 + C * exp(D * gamma) + E * cos_gamma * cos_gamma);
    // Reference radiance at zenith vs sun: simple analytic shape, not strict Preetham
    float thetaS = acos(max(sun_dir.y, 0.0));
    float F0 = (1.0 + A) * (1.0 + C * exp(D * thetaS) + E * cos(thetaS) * cos(thetaS));
    float Y  = max(F / F0, 0.0);

    // Color the sky: deeper blue away from sun, warm near horizon and sun
    float3 zenith = float3(0.10, 0.30, 0.85);
    float3 horiz  = float3(0.85, 0.78, 0.65);
    float3 sun_tint = float3(1.4, 1.1, 0.7);

    float horiz_w = pow(1.0 - cos_theta, 6.0);
    float3 base = mix(zenith, horiz, horiz_w);

    float sun_disc = smoothstep(0.9996, 0.99995, cos_gamma) * 50.0;
    float sun_glow = pow(max(cos_gamma, 0.0), 32.0) * 0.7;
    return base * Y + sun_tint * (sun_disc + sun_glow);
}

fragment float4 sky_fs(VOut in [[stage_in]],
                      constant SkyUniforms& U [[buffer(0)]]) {
    float4 a = U.inv_view_proj * float4(in.uv, 0.0, 1.0);
    float4 b = U.inv_view_proj * float4(in.uv, 1.0, 1.0);
    float3 dir = normalize(b.xyz / b.w - a.xyz / a.w);
    float3 col = preetham(dir, normalize(U.sun_dir), U.turbidity);
    // Simple tone-map for now
    col = col / (col + 1.0);
    return float4(col, 1.0);
}

struct CubeFaceUniforms {
    float3 right;
    float  _p0;
    float3 up;
    float  _p1;
    float3 forward;
    float  _p2;
    float3 sun_dir;
    float  turbidity;
};

vertex VOut sky_cube_vs(uint vid [[vertex_id]]) {
    return sky_vs_impl(vid);
}

fragment float4 sky_cube_fs(VOut in [[stage_in]],
                            constant CubeFaceUniforms& U [[buffer(0)]]) {
    float2 nd = in.uv; // [-1,1]
    float3 dir = normalize(U.forward + nd.x * U.right + nd.y * U.up);
    float3 col = preetham(dir, normalize(U.sun_dir), U.turbidity);
    return float4(col, 1.0); // store HDR-ish (clamped by texture format)
}
