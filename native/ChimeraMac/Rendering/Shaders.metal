#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float edge;
};

vertex VertexOut phosphor_vertex(uint vertexID [[vertex_id]], constant VertexIn *vertices [[buffer(0)]], constant float2 &viewport [[buffer(1)]]) {
    const VertexIn input = vertices[vertexID];
    VertexOut out;
    out.position = float4(input.position.x / viewport.x * 2.0 - 1.0, 1.0 - input.position.y / viewport.y * 2.0, 0.0, 1.0);
    out.color = input.color;
    out.edge = 0.0;
    return out;
}

fragment float4 phosphor_fragment(VertexOut input [[stage_in]]) {
    const float width = max(fwidth(input.edge), 0.001);
    const float coverage = 1.0 - smoothstep(1.0 - width, 1.0 + width, abs(input.edge));
    return float4(input.color.rgb, input.color.a * coverage);
}

struct Segment3D {
    float3 start;
    float3 end;
    float4 color;
    float width;
};

struct SegmentStyle {
    float extraWidth;
    float alpha;
};

vertex VertexOut phosphor_vertex_3d(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant Segment3D *segments [[buffer(0)]],
    constant float4x4 &viewProjection [[buffer(1)]],
    constant float2 &viewport [[buffer(2)]],
    constant SegmentStyle &style [[buffer(3)]],
    constant float4x4 &modelTransform [[buffer(4)]]
) {
    const uint ends[6] = {0, 0, 1, 0, 1, 1};
    const float sides[6] = {-1, 1, 1, -1, 1, -1};
    const Segment3D segment = segments[instanceID];
    const float4 startClip = viewProjection * modelTransform * float4(segment.start, 1.0);
    const float4 endClip = viewProjection * modelTransform * float4(segment.end, 1.0);
    const float2 startScreen = (startClip.xy / startClip.w * 0.5 + 0.5) * viewport;
    const float2 endScreen = (endClip.xy / endClip.w * 0.5 + 0.5) * viewport;
    const float2 delta = endScreen - startScreen;
    const float2 normal = float2(-delta.y, delta.x) / max(length(delta), 0.001);
    float4 clip = ends[vertexID] == 0 ? startClip : endClip;
    const float2 offset = normal * sides[vertexID] * (segment.width + style.extraWidth) * 0.5 / viewport * 2.0 * clip.w;
    clip = float4(clip.xy + offset, clip.z, clip.w);
    VertexOut out;
    out.position = clip;
    out.color = float4(segment.color.rgb, segment.color.a * style.alpha);
    out.edge = sides[vertexID];
    return out;
}
