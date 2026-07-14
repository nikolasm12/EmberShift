#include <metal_stdlib>
using namespace metal;

struct RasterData {
    float4 position [[position]];
    float2 textureCoordinate;
};

struct FilterUniforms {
    float redGain;
    float dimming;
    float2 padding;
};

vertex RasterData redLuminanceVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    const float2 textureCoordinates[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    RasterData output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.textureCoordinate = textureCoordinates[vertexID];
    return output;
}

float3 srgbToLinear(float3 value) {
    return select(
        value / 12.92,
        pow((value + 0.055) / 1.055, float3(2.4)),
        value > 0.04045
    );
}

float3 linearToSRGB(float3 value) {
    value = max(value, 0.0);
    return select(
        value * 12.92,
        1.055 * pow(value, float3(1.0 / 2.4)) - 0.055,
        value > 0.0031308
    );
}

fragment float4 redLuminanceFragment(
    RasterData input [[stage_in]],
    texture2d<float> capturedTexture [[texture(0)]],
    constant FilterUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    const float3 capturedSRGB = capturedTexture.sample(
        textureSampler,
        input.textureCoordinate
    ).rgb;
    const float3 capturedLinear = srgbToLinear(capturedSRGB);
    const float luminance = dot(
        capturedLinear,
        float3(0.2126, 0.7152, 0.0722)
    );
    const float red = saturate(
        luminance * uniforms.redGain * (1.0 - uniforms.dimming)
    );
    return float4(linearToSRGB(float3(red, 0.0, 0.0)), 1.0);
}
