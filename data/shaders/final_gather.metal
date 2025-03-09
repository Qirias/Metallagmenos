#define METAL
#include <metal_stdlib>
using namespace metal;

#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
#if USE_EYE_DEPTH
    float3 eye_position;
#endif
};

vertex VertexOut final_gather_vertex(uint       vertexID	[[vertex_id]],
                            constant FrameData& frameData 	[[buffer(BufferIndexFrameData)]]) {
    VertexOut out;

    float2 position = float2((vertexID << 1) & 2, vertexID & 2);
    out.position = float4(position * 2.0f - 1.0f, 0.0f, 1.0f);
    out.texCoords = position;

#if USE_EYE_DEPTH
    float4 unprojected_eye_coord = frameData.projection_matrix_inverse * out.position;
    out.eye_position = unprojected_eye_coord.xyz / unprojected_eye_coord.w;
#endif

    return out;
}

fragment AccumLightBuffer final_gather_fragment(VertexOut           in              [[stage_in]],
                                       constant FrameData&          frameData       [[buffer(BufferIndexFrameData)]],
                                                texture2d<float>    radianceTexture [[texture(TextureIndexRadiance)]],
                                                GBufferData         GBuffer) {
    half3 albedo = GBuffer.albedo_specular.rgb;
    half3 normal = normalize(GBuffer.normal_map.xyz);

    float2 texCoords = float2(in.texCoords.x, 1.0 - in.texCoords.y);
    float4 radianceSample = radianceTexture.sample(samplerLinear, texCoords);

    float3 upVector = float3(0.0, 1.0, 0.0);
    float normalFactor = max(0.0, dot(float3(normal), upVector) * 0.5 + 0.5);

    half3 normalRadiance = half3(radianceSample.rgb) * normalFactor;
    half3 finalColor = albedo * (normalRadiance);

    AccumLightBuffer output;
    output.lighting = half4(finalColor, 1.0h);

    return output;
}
