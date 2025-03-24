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

fragment AccumLightBuffer final_gather_fragment(VertexOut           in                  [[stage_in]],
                                    constant    FrameData&          frameData           [[buffer(BufferIndexFrameData)]],
                                                texture2d<float>    radianceTextureMin  [[texture(TextureIndexRadianceMin)]],
                                                texture2d<float>    radianceTextureMax  [[texture(TextureIndexRadianceMax)]],
                                                texture2d<float>    minMaxDepthTexture  [[texture(TextureIndexMinMaxDepth)]],
                                                GBufferData         GBuffer) {
    half4 albedoSpecular = GBuffer.albedo_specular;
    half3 albedo = albedoSpecular.rgb;
    half3 normal = normalize(GBuffer.normal_map.xyz);
    bool isEmissive = (GBuffer.normal_map.a == -1);
    AccumLightBuffer output;
    half3 finalColor;
    
    // Early exit for emissive surfaces
    if (isEmissive) {
        float3 lightDir = normalize(float3(0.0, 1.0, 0.0));
        half shading = max(0.0h, dot(normal, half3(lightDir))) * 0.5h + 0.5h;
        finalColor = albedo * shading;
        output.lighting = half4(finalColor * 2.0, 1.0h);
        return output;
    }
    
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

    // Calculate weighted min/max depths from surrounding probes
    float2 weightedMinMaxDepth = float2(0.0f);
    
    for (int i = 0; i < 4; i++) {
        float2 probeIdx = clamp(probeBase + probeOffsets[i], float2(0.0), probeGridSize - 1.0);
        float2 probeUV = (probeIdx + 0.5f) / probeGridSize;
        float2 minMaxDepth = minMaxDepthTexture.sample(depthSampler, probeUV).xy;
        weightedMinMaxDepth += minMaxDepth * bilinearWeights[i];
    }
    
    float pixelDepth = minMaxDepthTexture.sample(depthSampler, texCoords, level(0)).x;
    
    float depthThickness = max(weightedMinMaxDepth.y - weightedMinMaxDepth.x, 0.001f);
    
    // Calculate normalized position of pixel depth between min and max depths
    float depthWeight = saturate((pixelDepth - weightedMinMaxDepth.x) / depthThickness);
    
    // Apply spatial-only (bilinear) sampling to each of min/max textures
    float4 probeRadianceMin[4];
    float4 probeRadianceMax[4];
    
    for (int i = 0; i < 4; i++) {
        float2 probeIdx = clamp(probeBase + probeOffsets[i], float2(0.0), probeGridSize - 1.0);
        float2 probeBaseUV = probeIdx * probeTileSize * texelSize;
        
        float4 radianceSumMin = float4(0.0);
        float4 radianceSumMax = float4(0.0);
        float totalWeight = 0.0;
        
        // Sample with cosine weighting
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                float2 dirUV = float2((x + 0.5f) * 0.25f, (y + 0.5f) * 0.25f);
                float3 direction = oct_decode(dirUV);
                float weight = max(0.0, dot(float3(normal), direction));
                float2 sampleUV = probeBaseUV + dirUV * (probeTileSize * texelSize);
                
                float4 sampleMin = radianceTextureMin.sample(samplerLinear, sampleUV);
                float4 sampleMax = radianceTextureMax.sample(samplerLinear, sampleUV);
                
                radianceSumMin += sampleMin * weight;
                radianceSumMax += sampleMax * weight;
                totalWeight += weight;
            }
        }
        
        probeRadianceMin[i] = (totalWeight > 0) ? (radianceSumMin / totalWeight) : float4(0.0);
        probeRadianceMax[i] = (totalWeight > 0) ? (radianceSumMax / totalWeight) : float4(0.0);
    }
    
    // Spatial interpolation for min and max
    float4 radiance_min = probeRadianceMin[0] * bilinearWeights.x +
                          probeRadianceMin[1] * bilinearWeights.y +
                          probeRadianceMin[2] * bilinearWeights.z +
                          probeRadianceMin[3] * bilinearWeights.w;
                          
    float4 radiance_max = probeRadianceMax[0] * bilinearWeights.x +
                          probeRadianceMax[1] * bilinearWeights.y +
                          probeRadianceMax[2] * bilinearWeights.z +
                          probeRadianceMax[3] * bilinearWeights.w;
    
    // Trilinear interpolation
    float4 finalRadiance = mix(radiance_min, radiance_max, depthWeight);
    
    finalColor = albedo * half3(finalRadiance.rgb);
    
    // For debugging
//     finalColor = half3(depthWeight, depthWeight, depthWeight); // Shows grayscale depth weight
//    finalColor = half3(depthThickness, depthThickness, depthThickness);
    // finalColor = half3(depthWeight, 0.0, 1.0-depthWeight);     // Shows blend factor as color (red=max, blue=min)
    
    output.lighting = half4(finalColor, 1.0h);
    return output;
}
