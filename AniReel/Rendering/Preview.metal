#include <metal_stdlib>
using namespace metal;

struct PreviewVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex PreviewVertexOut previewVertex(uint vid [[vertex_id]], constant float2 &scale [[buffer(0)]])
{
    const float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    const float2 uvs[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    PreviewVertexOut out;
    out.position = float4(positions[vid] * scale, 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 previewFragment(PreviewVertexOut in [[stage_in]], texture2d<float> frame [[texture(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return frame.sample(s, in.uv);
}
