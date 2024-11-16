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

// Vertex shader that generates a full-screen triangle with frameData
vertex VertexOut deferred_directional_lighting_vertex(uint 				vertexID	[[vertex_id]],
										   constant FrameData& 			frameData 	[[buffer(2)]]) {
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
														constant FrameData& 			frameData 	[[buffer(2)]],
																 GBufferData 			GBuffer) {
	// Get the data from GBuffer
	half4 albedo_specular = GBuffer.albedo_specular;
	half4 normal_shadow = GBuffer.normal_shadow;
	float depth = GBuffer.depth;
	
	half3 albedo = albedo_specular.rgb;
	half specularIntensity = albedo_specular.a;
	
	// Reconstruct world position from depth
	float4 clipSpacePosition = float4(in.texCoords * 2.0 - 1.0, depth, 1.0);
	float4 viewSpacePosition = frameData.projection_matrix_inverse * clipSpacePosition;
	viewSpacePosition /= viewSpacePosition.w;
	
	// Calculate lighting vectors
	float3 lightDir = normalize(-frameData.sun_eye_direction.xyz);
	float3 viewDir = normalize(-viewSpacePosition.xyz);
	float3 halfDir = normalize(lightDir + viewDir);
	
	// Convert to half for calculations with GBuffer data
	half3 normal_shadow_xyz = normal_shadow.xyz;
	half3 lightDir_half = half3(lightDir);
	half3 halfDir_half = half3(halfDir);
	
	// Add ambient lighting parameters
	const half3 ambientColor = half3(1.0h);
	const half ambientIntensity = 0.4h;

	// Calculate ambient term
	half3 ambient = ambientColor * albedo * ambientIntensity;
	
	// Diffuse lighting
	half NdotL = max(dot(normal_shadow_xyz, lightDir_half), 0.0h);
	half3 diffuse = half3(frameData.sun_color.rgb) * albedo * NdotL;
	
	// Specular lighting
	half shininess_factor = 1.0h; // Add to frameData later
	half specular_shininess = specularIntensity * shininess_factor;
	half NdotH = max(dot(normal_shadow_xyz, halfDir_half), 0.0h);
	half3 specular = half3(frameData.sun_color.rgb) *
					powr(NdotH, half(frameData.sun_specular_intensity)) *
					specular_shininess;
	
	// Get shadow factor from GBuffer
	half shadowFactor = normal_shadow.w;
	// Lighten the shadow to account for some ambience
	shadowFactor = saturate(shadowFactor + 0.1h);
	
	// Combine lighting components
	half3 finalColor = ambient + (diffuse + specular) * shadowFactor;
	
	// Output to AccumLightBuffer
	AccumLightBuffer output;
	output.lighting = half4(finalColor, 1.0h);
	
	return output;
}
