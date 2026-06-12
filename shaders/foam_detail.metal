#include <metal_stdlib>
using namespace metal;

// One-time bake (design §5): tileable foam micro-structure. Inverted-F1
// Worley CLUMPS (bright blobs at cell features) at three octaves, broken up
// by wrapped value noise. Clump topology is load-bearing: F2-F1 cell-wall
// ridges form a connected Voronoi-edge net that reads as spiderwebs draped
// on the water — disconnected blobs read as foam. All lattices wrap at their
// cell count, so the texture tiles seamlessly. Output mean ~0.55 so the
// mask erosion keeps coverage.

static float2 cell_hash(int2 p, int period) {
    p = ((p % period) + period) % period;            // wrapped lattice
    uint h = (uint)p.x * 374761393u + (uint)p.y * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= (h >> 16);
    return float2(h & 0xFFFFu, (h >> 16) & 0xFFFFu) / 65535.0;
}

static float worley_blob(float2 uv, int cells) {
    float2 g = uv * (float)cells;
    int2 base = int2(floor(g));
    float f1 = 1e9;
    for (int dy = -1; dy <= 1; ++dy)
        for (int dx = -1; dx <= 1; ++dx) {
            int2 cell = base + int2(dx, dy);
            float2 feat = float2(cell) + cell_hash(cell, cells);
            f1 = min(f1, distance(g, feat));
        }
    // Inverted F1: bright at the feature, dark toward the cell border. The
    // falloff keeps the blob's support at ~65% of the cell radius — at wider
    // support adjacent blobs tile edge-to-edge and the *Voronoi cell lattice*
    // becomes the visible structure (reads as blocky polygons, not clumps).
    // Smoothstep rim: a hard saturate edge is a C1 discontinuity that pumps
    // high-frequency energy into the mip chain (aliases to gridded moiré).
    float s = saturate(1.0 - f1 * 1.55);
    return s * s * (3.0 - 2.0 * s);
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

    // Band-limited per mip level: this kernel is dispatched once per mip
    // (the texture is NOT box-mipped — see bake_foam_detail_if_needed). An
    // octave whose cells span < ~4 texels at this resolution cannot be
    // represented without aliasing; fade it out and renormalize. At 512
    // (mip 0) all admittances are 1 and the result matches the flat sum.
    const float ow[3] = {0.55, 0.30, 0.15};
    const int   oc[3] = {8, 19, 41};
    float clump = 0.0, wsum = 0.0;
    for (int o = 0; o < 3; ++o) {
        float texels_per_cell = (float)S / (float)oc[o];
        float admit = saturate(texels_per_cell / 4.0 - 0.5);
        clump += ow[o] * admit * worley_blob(uv, oc[o]);
        wsum  += ow[o] * admit;
    }
    clump = wsum > 1e-4 ? clump / wsum : 0.0;
    float vn = value_noise(uv, 7);
    float r = saturate(clump * (0.55 + 0.9 * vn));
    out.write(float4(r, r, r, 1.0), gid);
}
