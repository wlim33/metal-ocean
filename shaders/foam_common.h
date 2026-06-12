#pragma once
// Foam/whitecap math shared between GPU kernels (foam_update.metal,
// ocean_surface.metal) and CPU tests (tests/foam_test.cpp). Tests must stay
// Metal-free, so the formulas live here where a plain C++ translation unit
// can execute the exact arithmetic the GPU runs.
//
// Reference: Dupuy & Bruneton 2012, "Real-time Animation and Rendering of
// Ocean Whitecaps" — k-share decomposition (eq. 7) and erf coverage (eq. 6).

// -- stdlib dispatch shims: internal, not part of the foam API --
#ifdef __METAL_VERSION__
inline float foamc_exp(float x)   { return metal::exp(x); }
inline float foamc_abs(float x)   { return metal::fabs(x); }
inline float foamc_rsqrt(float x) { return metal::rsqrt(x); }
#else
#include <cmath>
inline float foamc_exp(float x)   { return std::exp(x); }
inline float foamc_abs(float x)   { return std::fabs(x); }
inline float foamc_rsqrt(float x) { return 1.0f / std::sqrt(x); }
#endif

// One cascade's share of the multi-cascade displacement Jacobian:
//   k = 1/n + a + b + a·b − c²
// with a = λ·∂Dx/∂x, b = λ·∂Dz/∂z, c = λ·∂Dx/∂z (= λ·∂Dz/∂x — the choppy
// displacement is a gradient field, so the Jacobian is symmetric) and n the
// cascade count. Σk_i equals the full Jacobian up to zero-mean cross terms.
inline float foamc_k_term(float a, float b, float c, float inv_n) {
    return inv_n + a + b + a * b - c * c;
}

// Standalone Jacobian of one cascade as if it were alone on the surface.
// post_fft.metal stores this in normal.w; k is recovered algebraically.
inline float foamc_j_own(float k, float inv_n) { return k + (1.0f - inv_n); }

// Abramowitz–Stegun 7.1.26 rational erf approximation, |error| <= 1.5e-7.
// MSL has no erf builtin.
inline float foamc_erf(float x) {
    const float p  = 0.3275911f;
    const float a1 = 0.254829592f, a2 = -0.284496736f, a3 = 1.421413741f;
    const float a4 = -1.453152027f, a5 = 1.061405429f;
    float sign_ = x < 0.0f ? -1.0f : 1.0f;
    float ax = foamc_abs(x);
    float t = 1.0f / (1.0f + p * ax);
    float poly = ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t;
    return sign_ * (1.0f - poly * foamc_exp(-ax * ax));
}

// Anti-aliased whitecap coverage W = P(J < eps) for J ~ N(mu, sigma2)
// (D&B eq. 6): W = 1/2 + 1/2·erf((eps − mu)/(σ√2)). Falls back to a step
// when the footprint variance vanishes (mip 0, calm seas).
inline float foamc_coverage(float eps, float mu, float sigma2) {
    // Threshold sits above the fp16 quantization noise floor of the stored
    // moments (k quantum ~1e-3 near k=1, so k² residuals reach ~1e-5..1e-3):
    // genuine footprint variance under minification is larger; anything
    // smaller is sensor noise and must take the clean step, not a noisy erf.
    if (sigma2 < 2e-3f) return mu < eps ? 1.0f : 0.0f;
    return 0.5f + 0.5f * foamc_erf((eps - mu) * foamc_rsqrt(2.0f * sigma2));
}

// Per-frame exponential decay multiplier. dt is clamped to [0, 0.1 s] so a
// debugger pause or hitch cannot flush the persistent foam buffer; tau is
// floored at 1 ms to guard against zero/invalid config values.
inline float foamc_decay_factor(float dt_seconds, float tau_seconds) {
    float dt  = dt_seconds < 0.0f ? 0.0f : (dt_seconds > 0.1f ? 0.1f : dt_seconds);
    float tau = tau_seconds < 1e-3f ? 1e-3f : tau_seconds;
    return foamc_exp(-dt / tau);
}
