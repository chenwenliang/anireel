#include <metal_stdlib>
using namespace metal;

struct ChibiParams {
    float spread;
    float levels;
    float saturation;
    float outlineWidth;
    float outlineLow;
    float outlineHigh;
};

static float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

static float sobel(texture2d<float, access::sample> src, sampler s, float2 uv, float2 tap) {
    float l[9];
    int k = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            l[k++] = luma(src.sample(s, uv + float2(x, y) * tap).rgb);
        }
    }
    float gx = -l[0] - 2.0 * l[3] - l[6] + l[2] + 2.0 * l[5] + l[8];
    float gy = -l[0] - 2.0 * l[1] - l[2] + l[6] + 2.0 * l[7] + l[8];
    return length(float2(gx, gy));
}

// Two blur rings round off detail into blocks, few bright bands with lifted saturation,
// and a wide-tap Sobel for thick outlines.
kernel void chibiPost(texture2d<float, access::sample> src [[texture(0)]],
                      texture2d<float, access::write> dst [[texture(1)]],
                      constant ChibiParams &p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 tap = p.spread / size;

    float3 sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += src.sample(s, uv + float2(x, y) * tap).rgb;
            sum += src.sample(s, uv + float2(x, y) * tap * 2.0).rgb;
        }
    }
    float3 color = sum / 18.0;

    float lum = luma(color);
    float banded = (floor(lum * p.levels) + 0.6) / p.levels;
    color *= banded / max(lum, 1e-3);
    color = mix(float3(luma(color)), color, p.saturation);
    color = color * 0.92 + 0.1;

    float edge = smoothstep(p.outlineLow, p.outlineHigh, sobel(src, s, uv, p.outlineWidth / size));
    color = mix(color, float3(0.2, 0.1, 0.16), edge);

    dst.write(float4(saturate(color), 1.0), gid);
}
