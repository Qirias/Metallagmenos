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
    
    const uint tileSize = 2;
    const uint probeGridSizeX = (frameData.framebuffer_width + tileSize - 1) / tileSize;
    const uint probeGridSizeY = (frameData.framebuffer_height + tileSize - 1) / tileSize;
    
    float2 gridCoord = texCoords * float2(probeGridSizeX, probeGridSizeY) - 0.5f;
    int2 probeBase = int2(floor(gridCoord));
    float2 probeFrac = fract(gridCoord);
    
    // Bilinear weights for the four nearest probes
    float4 weights = float4(
        (1.0f - probeFrac.x) * (1.0f - probeFrac.y),  // Bottom-Left
        probeFrac.x * (1.0f - probeFrac.y),           // Bottom-Right
        (1.0f - probeFrac.x) * probeFrac.y,           // Top-Left
        probeFrac.x * probeFrac.y                     // Top-Right
    );
    
    int2 probeOffsets[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};
    
    float3 accumulatedRadiance = float3(0.0);
    float totalWeight = 0.0;
    
    // Sample the 4 nearest probes
    for (int i = 0; i < 4; i++) {
        int2 probeCoord = probeBase + probeOffsets[i];
        
        probeCoord = clamp(probeCoord, int2(0, 0), int2(probeGridSizeX-1, probeGridSizeY-1));
        
        float weight = weights[i];
        if (weight <= 0.0f) continue;
        
        float2 probeUV = (float2(probeCoord) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
        
        float4 radiance = radianceTexture.sample(samplerLinear, probeUV);
        
        accumulatedRadiance += radiance.rgb * weight;
        totalWeight += weight;
    }
    
    float3 finalRadiance = totalWeight > 0.0f ? accumulatedRadiance / totalWeight : float3(0.0);
    
    float3 upVector = float3(0.0, 1.0, 0.0);
    float normalFactor = max(0.0, dot(float3(normal), upVector) * 0.5 + 0.5);
    
    float3 normalModulatedRadiance = finalRadiance * normalFactor;
    
    half3 finalColor = albedo * half3(normalModulatedRadiance);
    
    AccumLightBuffer output;
    output.lighting = half4(finalColor, 1.0h);
    
    return output;
}
