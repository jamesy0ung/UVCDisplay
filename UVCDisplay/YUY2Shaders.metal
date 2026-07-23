//
//  YUY2Shaders.metal
//  UVCDisplay
//

#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

struct YUY2Params {
    uint width;
    uint height;
};

vertex VSOut yuy2_vertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VSOut o;
    o.position = float4(p[vid], 0.0, 1.0);
    o.uv = float2(p[vid].x * 0.5 + 0.5, 1.0 - (p[vid].y * 0.5 + 0.5));
    return o;
}

fragment float4 yuy2_fragment(VSOut in [[stage_in]],
                              device const uchar *yuy2 [[buffer(0)]],
                              constant YUY2Params &params [[buffer(1)]]) {
    int w = int(params.width);
    int h = int(params.height);

    int x = clamp(int(in.uv.x * float(w)), 0, w - 1);
    int y = clamp(int(in.uv.y * float(h)), 0, h - 1);

    int  idx  = y * w * 2 + x * 2;
    bool even = (x & 1) == 0;

    const float inv255 = 1.0 / 255.0;
    float Y = float(yuy2[idx]) * inv255;
    float U = float(yuy2[even ? idx + 1 : idx - 1]) * inv255;
    float V = float(yuy2[even ? idx + 3 : idx + 1]) * inv255;

    // BT.709 limited range (16-235 luma, 16-240 chroma).
    float y_ = 1.164 * (Y - 0.0627);
    float u = U - 0.5;
    float v = V - 0.5;
    float r = y_ + 1.793 * v;
    float g = y_ - 0.213 * u - 0.533 * v;
    float b = y_ + 2.112 * u;

    return float4(clamp(float3(r, g, b), 0.0, 1.0), 1.0);
}

fragment float4 rgb_scaling_fragment(VSOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear,
                        s_address::clamp_to_edge, t_address::clamp_to_edge);
    return tex.sample(s, in.uv);
}
