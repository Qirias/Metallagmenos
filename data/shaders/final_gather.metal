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

vertex VertexOut final_gather_vertex(uint       vertexID [[vertex_id]],
                             constant FrameData& frameData [[buffer(BufferIndexFrameData)]]) {
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

float2 sign_NotZero(float2 v) {
    return float2((v.x >= 0.0) ? +1.0 : -1.0, (v.y >= 0.0) ? +1.0 : -1.0);
}

float2 oct_encode(float3 n) {
    float2 p = n.xy * (1.0 / (abs(n.x) + abs(n.y) + abs(n.z)));
    p = (n.z <= 0.0) ? ((1.0 - abs(p.yx)) * sign_NotZero(p)) : p;
    return p * 0.5 + 0.5; // -1,1 to 0,1
}

float3 oct_decode(float2 f) {
    f = f * 2.0 - 1.0; // 0,1 to -1,1
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    if (n.z < 0)
        n.xy = (1.0 - abs(n.yx)) * sign_NotZero(n.xy);
    return normalize(n);
}

fragment AccumLightBuffer final_gather_fragment(VertexOut           in              [[stage_in]],
                                    constant    FrameData&          frameData       [[buffer(BufferIndexFrameData)]],
                                                texture2d<float>    radianceTexture [[texture(TextureIndexRadiance)]],
                                                GBufferData         GBuffer) {
    half4 albedoSpecular = GBuffer.albedo_specular;
    half3 albedo = albedoSpecular.rgb;
    half3 normal = normalize(GBuffer.normal_map.xyz);
    bool isEmissive = (GBuffer.normal_map.a == -1);
    AccumLightBuffer output;
    half3 finalColor;
    
    float2 texCoords = float2(in.texCoords.x, 1.0 - in.texCoords.y);
    float2 probeGridSize = float2(frameData.framebuffer_width * 0.25, frameData.framebuffer_height * 0.25);

    float2 probeCoord = texCoords * probeGridSize;
    float2 probeBase = floor(probeCoord);
    float2 probeFrac = fract(probeCoord);

    float2 probeOffsets[4] = {float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1)};
    float4 bilinearWeights = float4((1.0f - probeFrac.x) * (1.0f - probeFrac.y),
                                    probeFrac.x * (1.0f - probeFrac.y),
                                    (1.0f - probeFrac.x) * probeFrac.y,
                                    probeFrac.x * probeFrac.y);

    const float probeTileSize = 4.0f;
    const float texelSize = 1.0f / (probeGridSize.x * probeTileSize);

    float4 probeRadiance[4];
    for (int i = 0; i < 4; i++) {
        float2 probeIdx = clamp(probeBase + probeOffsets[i], float2(0.0), probeGridSize - 1.0);
        float2 probeBaseUV = probeIdx * probeTileSize * texelSize;

        float4 radianceSum = float4(0.0);
        if (isEmissive) {
            float3 lightDir = normalize(float3(0.0, 1.0, 0.0)); 
            half shading = max(0.0h, dot(normal, half3(lightDir))) * 0.5h + 0.5h;
            finalColor = albedo * shading;
            output.lighting = half4(finalColor*2.0, 1.0h);
            return output;
        } else {
            // Non-emissive: Weight by cosine law
            float totalWeight = 0.0;
            for (int y = 0; y < 4; y++) {
                for (int x = 0; x < 4; x++) {
                    float2 dirUV = float2((x + 0.5f) * 0.25f, (y + 0.5f) * 0.25f);
                    float3 direction = oct_decode(dirUV);
                    float weight = max(0.0, dot(float3(normal), direction));
                    float2 sampleUV = probeBaseUV + dirUV * (probeTileSize * texelSize);
                    float4 sample = radianceTexture.sample(samplerLinear, sampleUV);
                    radianceSum += sample * weight;
                    totalWeight += weight;
                }
            }
            probeRadiance[i] = (totalWeight > 0) ? radianceSum / totalWeight : float4(0.0);
        }
    }

    float4 radiance = probeRadiance[0] * bilinearWeights.x +
                      probeRadiance[1] * bilinearWeights.y +
                      probeRadiance[2] * bilinearWeights.z +
                      probeRadiance[3] * bilinearWeights.w;

    finalColor = albedo * half3(radiance.rgb);
    
    output.lighting = half4(finalColor, 1.0h);
    return output;
}
