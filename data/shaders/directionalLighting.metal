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

vertex VertexOut deferred_directional_lighting_vertex(uint 				vertexID	[[vertex_id]],
										   constant FrameData& 			frameData 	[[buffer(BufferIndexFrameData)]]) {
    VertexOut out;

    // Generate full-screen triangle
    float2 position = float2((vertexID << 1) & 2, vertexID & 2);
    out.position = float4(position * 2.0f - 1.0f, 0.0f, 1.0f);
    out.texCoords = position;

#if USE_EYE_DEPTH
    float4 unprojected_eye_coord = frameData.projection_matrix_inverse * out.position;
    out.eye_position = unprojected_eye_coord.xyz / unprojected_eye_coord.w;
#endif

    return out;
}

fragment AccumLightBuffer deferred_directional_lighting_fragment(VertexOut 				in 			[[stage_in]],
														constant FrameData& 			frameData 	[[buffer(BufferIndexFrameData)]],
																 GBufferData 			GBuffer) {
    // Extract albedo and normals from the GBuffer
    half4 albedo_specular = GBuffer.albedo_specular;
    half4 normal_map = GBuffer.normal_map;

    half3 albedo = albedo_specular.rgb;
    half3 normal = normalize(normal_map.xyz); // Use the normal from the GBuffer

    // Simulate a directional light
    float3 lightDir = normalize(-frameData.sun_eye_direction.xyz); // Directional light from the sun
    half NdotL = max(dot(normal, half3(lightDir)), 0.0h);

    // Combine albedo and the diffuse term
    half3 finalColor = albedo * NdotL;

    // Output the final color
    AccumLightBuffer output;
    output.lighting = half4(finalColor, 1.0h);

    return output;
}
