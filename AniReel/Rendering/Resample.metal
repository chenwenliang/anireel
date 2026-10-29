#include <metal_stdlib>
using namespace metal;

kernel void styleResample(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
    dst.write(float4(src.sample(s, uv).rgb, 1.0), gid);
}

/// Shown while a style's model is missing or failed: the camera picture in dim grey, so it can
/// never be mistaken for a style. Such frames are not recorded.
kernel void styleUnavailable(texture2d<float, access::sample> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
    float luma = dot(src.sample(s, uv).rgb, float3(0.299, 0.587, 0.114));
    dst.write(float4(float3(luma * 0.35), 1.0), gid);
}
