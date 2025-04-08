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

vertex VertexOut final_gather_vertex(uint       vertexID    [[vertex_id]],
                            constant FrameData& frameData   [[buffer(BufferIndexFrameData)]]) {
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

half3 gammaCorrect(half3 linear) {
    return pow(linear, 1.0f / 2.2f);
}

half3 acesTonemap(half3 color) {
    half3 a = 2.51h;
    half3 b = 0.03h;
    half3 c = 2.43h;
    half3 d = 0.59h;
    half3 e = 0.14h;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

half3 postProcessColor(half3 color) {
    color = acesTonemap(color);
    color = gammaCorrect(color);
    
    return color;
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

fragment half4 final_gather_fragment(VertexOut           in              [[stage_in]],
                         constant    FrameData&          frameData       [[buffer(BufferIndexFrameData)]],
                                     texture2d<float>    radianceTexture [[texture(TextureIndexRadiance)]],
                                     texture2d<half>     albedoTexture   [[texture(TextureIndexBaseColor)]],
                                     texture2d<half>     normalTexture   [[texture(TextureIndexNormal)]],
                                     texture2d<float>    depthTexture    [[texture(TextureIndexDepthTexture)]],
                         constant    bool&               doBilinear      [[buffer(3)]]) {
    float2 texCoords = float2(in.texCoords.x, 1.0 - in.texCoords.y);
    
    // Sample G-Buffer textures
    half4 albedoSpecular = half4(albedoTexture.sample(samplerLinear, texCoords));
    half3 albedo = albedoSpecular.rgb;
    half4 normalRaw = half4(normalTexture.sample(samplerLinear, texCoords));
    half3 normal = normalize(normalRaw.xyz);
    float currentDepth = depthTexture.sample(samplerLinear, texCoords).x;

    bool isEmissive = (normalRaw.a == -1);
    
    // Handle emissive surfaces directly
    if (isEmissive) {
        half3 lightDir = normalize(half3(0.0, 1.0, 0.0));
        float shading = max(0.0h, dot(normal, half3(lightDir))) * 0.5h + 0.5h;
        half3 finalColor = albedo * shading * 2.0h;
        return half4(finalColor, 1.0h);
    }

    if (!doBilinear) {
        float4 radiance = radianceTexture.sample(samplerLinear, texCoords);
        
        half3 upVector = half3(0.0, 1.0, 0.0);
        half normalFactor = max(0.0h, dot(half3(normal), upVector) * 0.5h + 0.5h);
        
        half3 normalModulatedRadiance = half3(radiance.rgb) * normalFactor;
        half3 finalColor = albedo * normalModulatedRadiance;
        
        return half4(finalColor, 1.0);
    }

    // Calculate probe grid coordinates
    float2 probeGridSize = float2(frameData.framebuffer_width * 0.25, frameData.framebuffer_height * 0.25);
    float2 probeCoord = texCoords * probeGridSize - 0.5f;
    int2 probeBase = int2(floor(probeCoord));
    float2 probeFrac = fract(probeCoord);
    
    // Default bilinear weights
    float4 bilinearWeights = float4((1.0f - probeFrac.x) * (1.0f - probeFrac.y),
                                   probeFrac.x * (1.0f - probeFrac.y),
                                   (1.0f - probeFrac.x) * probeFrac.y,
                                   probeFrac.x * probeFrac.y);

    int2 probeOffsets[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};
    float4 probeDepths;
    int2 probeCoords[4];
    float2 probeUVs[4];
    
    for (int i = 0; i < 4; i++) {
        probeCoords[i] = int2(probeBase) + probeOffsets[i];
        probeCoords[i] = clamp(probeCoords[i], int2(0), int2(probeGridSize) - 1);
        probeUVs[i] = (float2(probeCoords[i]) + 0.5f) / probeGridSize;
        probeDepths[i] = depthTexture.sample(samplerLinear, probeUVs[i]).x;
    }

    float mind = min(min(probeDepths.x, probeDepths.y), min(probeDepths.z, probeDepths.w));
    float maxd = max(max(probeDepths.x, probeDepths.y), max(probeDepths.z, probeDepths.w));
    float diffd = maxd - mind;
    float avg = dot(probeDepths, float4(0.25f));
    bool d_edge = (diffd / avg) > 0.1;

    float4 w = bilinearWeights;
    if (d_edge) {
        float4 dd = abs(probeDepths - float4(currentDepth));
        w *= float4(1.0f) / (dd + float4(0.0001f));
    }
    
    float wsum = w.x + w.y + w.z + w.w;
    w /= wsum;

    const uint probeTileSize = 4;
    const float probeTexelSize = 1.0f / (probeGridSize.x * probeTileSize);

    float4 probeRadiance[4];
    
    for (int probeIdx = 0; probeIdx < 4; probeIdx++) {
        
        float2 probeBaseUV = float2(probeCoords[probeIdx]) * probeTileSize * probeTexelSize;
        float4 radianceSum = float4(0.0);
        float totalWeight = 0.0;
        
        // For each direction, sample and apply cosine weighting
        for (uint y = 0; y < probeTileSize; y++) {
            for (uint x = 0; x < probeTileSize; x++) {
                float2 dirUV = float2((x + 0.5f) / probeTileSize, (y + 0.5f) / probeTileSize);
                float3 direction = oct_decode(dirUV);
                float cosTheta = max(0.0, dot(float3(normal), direction));
                float2 sampleUV = probeBaseUV + dirUV * (probeTileSize * probeTexelSize);
                float4 sample = radianceTexture.sample(samplerLinear, sampleUV);
                
                radianceSum += sample * cosTheta;
                totalWeight += cosTheta;
            }
        }
        
        probeRadiance[probeIdx] = (totalWeight > 0.0001f) ? (radianceSum / totalWeight) : float4(0.0);
    }

    float4 finalRadiance = probeRadiance[0] * w.x +
                          probeRadiance[1]  * w.y +
                          probeRadiance[2]  * w.z +
                          probeRadiance[3]  * w.w;

    half3 finalColor = albedo * half3(finalRadiance.rgb);
    
    return half4(postProcessColor(finalColor), 1.0h);
}
