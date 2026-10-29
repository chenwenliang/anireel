// Metal approximation from before the Core ML switch. No style uses it any more
// (docs/COREML_RESULTS.md); kept as a standalone Metal module, never as a stand-in for a model.
#include <metal_stdlib>
using namespace metal;

struct NPRParams {
    float levels;
    float saturation;
    float edgeLow;
    float edgeHigh;
    float paperStrength;
};

static float nprLuma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

static float nprHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float nprValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = nprHash(i);
    float b = nprHash(i + float2(1, 0));
    float c = nprHash(i + float2(0, 1));
    float d = nprHash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Posterized color + Sobel ink lines + static paper grain. No time input, so output is deterministic per frame.
kernel void nprStylize(texture2d<float, access::sample> src [[texture(0)]],
                       texture2d<float, access::write> dst [[texture(1)]],
                       constant NPRParams &p [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float2 tap = 1.5 / size;

    float3 sum = 0.0;
    float l[9];
    int k = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float3 c = src.sample(s, uv + float2(x, y) * tap).rgb;
            sum += c;
            l[k++] = nprLuma(c);
        }
    }

    float3 color = sum / 9.0;
    float lum = nprLuma(color);
    float banded = floor(lum * p.levels + 0.5) / p.levels;
    color *= banded / max(lum, 1e-3);
    color = mix(float3(nprLuma(color)), color, p.saturation);

    float gx = -l[0] - 2.0 * l[3] - l[6] + l[2] + 2.0 * l[5] + l[8];
    float gy = -l[0] - 2.0 * l[1] - l[2] + l[6] + 2.0 * l[7] + l[8];
    float edge = smoothstep(p.edgeLow, p.edgeHigh, length(float2(gx, gy)));
    color = mix(color, float3(0.09, 0.07, 0.11), edge);

    float2 fp = float2(gid);
    float grain = 0.6 * nprValueNoise(fp * 0.35) + 0.4 * nprValueNoise(fp * 0.06);
    color *= mix(1.0 - p.paperStrength, 1.0, grain);
    color *= float3(1.0, 0.985, 0.95);

    dst.write(float4(saturate(color), 1.0), gid);
}
