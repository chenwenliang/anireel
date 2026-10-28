#include <metal_stdlib>
using namespace metal;

struct GhibliParams {
    float spread;
    float levels;
    float saturation;
    float edgeStrength;
};

static float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

// Model-free stand-in: softened color, smooth palette bands, lifted warm tones and soft tinted edges.
kernel void ghibliApprox(texture2d<float, access::sample> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         constant GhibliParams &p [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 tap = p.spread / size;

    const float weights[9] = { 1, 2, 1, 2, 4, 2, 1, 2, 1 };
    float3 sum = 0.0;
    float l[9];
    int k = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float3 c = src.sample(s, uv + float2(x, y) * tap).rgb;
            sum += c * weights[k];
            l[k++] = luma(c);
        }
    }
    float3 color = sum / 16.0;

    float lum = luma(color);
    float scaled = lum * p.levels;
    float banded = (floor(scaled) + smoothstep(0.3, 0.7, fract(scaled))) / p.levels;
    color *= banded / max(lum, 1e-3);
    color = mix(float3(luma(color)), color, p.saturation);
    color = color * 0.9 + 0.07;
    color *= float3(1.03, 1.0, 0.93);

    float gx = -l[0] - 2.0 * l[3] - l[6] + l[2] + 2.0 * l[5] + l[8];
    float gy = -l[0] - 2.0 * l[1] - l[2] + l[6] + 2.0 * l[7] + l[8];
    float edge = smoothstep(0.2, 0.6, length(float2(gx, gy))) * p.edgeStrength;
    color = mix(color, color * float3(0.4, 0.38, 0.42), edge);

    dst.write(float4(saturate(color), 1.0), gid);
}
