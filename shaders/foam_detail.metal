#include <metal_stdlib>
using namespace metal;

// One-time bake (design §5): tileable foam micro-structure. Cell-wall Worley
// (F2-F1 webbing = bubble lace) at three octaves, broken up by wrapped value
// noise. All lattices wrap at their cell count, so the texture tiles
// seamlessly. Output mean is ~0.55 so the mask erosion keeps coverage.

static float2 cell_hash(int2 p, int period) {
    p = ((p % period) + period) % period;            // wrapped lattice
    uint h = (uint)p.x * 374761393u + (uint)p.y * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= (h >> 16);
    return float2(h & 0xFFFFu, (h >> 16) & 0xFFFFu) / 65535.0;
}

static float worley_web(float2 uv, int cells) {
    float2 g = uv * (float)cells;
    int2 base = int2(floor(g));
    float f1 = 1e9, f2 = 1e9;
    for (int dy = -1; dy <= 1; ++dy)
        for (int dx = -1; dx <= 1; ++dx) {
            int2 cell = base + int2(dx, dy);
            float2 feat = float2(cell) + cell_hash(cell, cells);
            float d = distance(g, feat);
            if (d < f1) { f2 = f1; f1 = d; }
            else if (d < f2) { f2 = d; }
        }
    return 1.0 - saturate((f2 - f1) * 2.2);           // bright cell walls
}

static float value_noise(float2 uv, int cells) {
    float2 g = uv * (float)cells;
    int2 base = int2(floor(g));
    float2 f = fract(g);
    f = f * f * (3.0 - 2.0 * f);
    float v00 = cell_hash(base + int2(0, 0), cells).x;
    float v10 = cell_hash(base + int2(1, 0), cells).x;
    float v01 = cell_hash(base + int2(0, 1), cells).x;
    float v11 = cell_hash(base + int2(1, 1), cells).x;
    return mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
}

kernel void foam_detail_kernel(
    texture2d<float, access::write> out [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint S = out.get_width();
    if (gid.x >= S || gid.y >= S) return;
    float2 uv = float2(gid) / (float)S;

    float web = 0.55 * worley_web(uv, 8)
              + 0.30 * worley_web(uv, 19)
              + 0.15 * worley_web(uv, 41);
    float vn = value_noise(uv, 7);
    float r = saturate(web * (0.55 + 0.9 * vn));
    out.write(float4(r, r, r, 1.0), gid);
}
