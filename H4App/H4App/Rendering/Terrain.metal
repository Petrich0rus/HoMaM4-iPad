#include <metal_stdlib>
using namespace metal;

// Keep in sync with TerrainQuad / TerrainUniforms in the Swift sources.
struct Quad {
    float2 position;
    ushort2 tile;
    ushort2 mask;
    ushort slice;
    ushort flags;
};

struct Uniforms {
    float2 center;      // map pixel at the middle of the view
    float2 viewSize;    // drawable size in device pixels
    float scale;        // device pixels per map pixel
};

struct VertexOut {
    float4 position [[position]];
    float2 local;
    float2 tile [[flat]];
    float2 mask [[flat]];
    uint slice [[flat]];
    uint flags [[flat]];
};

// One instance per quad, four vertices as a triangle strip.
vertex VertexOut terrainVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                               constant Quad *quads [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
    Quad q = quads[iid];
    float2 local = float2(vid & 1, vid >> 1) * float2(64.0, 32.0);
    float2 p = floor((q.position + local - u.center) * u.scale + 0.5);
    VertexOut out;
    out.position = float4(p.x * 2.0 / u.viewSize.x, -p.y * 2.0 / u.viewSize.y, 0.0, 1.0);
    out.local = local;
    out.tile = float2(q.tile);
    out.mask = float2(q.mask);
    out.slice = q.slice;
    out.flags = q.flags;
    return out;
}

// Result = tile colour, with opacity = tile alpha * transition mask (blended over what is already drawn).
fragment half4 terrainFragment(VertexOut in [[stage_in]],
                               texture2d_array<half> tiles [[texture(0)]], texture2d<half> masks [[texture(1)]]) {
    constexpr sampler nearest(coord::pixel, filter::nearest, address::clamp_to_edge);
    half4 colour = tiles.sample(nearest, in.tile + in.local, in.slice);
    half m = 1.0h;
    if (in.mask.x < 65535.0) {
        m = masks.sample(nearest, in.mask + in.local).r;
        if (in.flags & 1u) m = 1.0h - m;
    }
    half a = colour.a * m;
    if (a <= 0.0h) discard_fragment();
    return half4(colour.rgb, a);
}
