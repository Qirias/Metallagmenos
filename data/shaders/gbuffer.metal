#define METAL
#include <metal_stdlib>
using namespace metal;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

struct ColorInOut
{
	float4 position [[position]];
	float2 tex_coord;
	float3 eye_position;
	half3  tangent;
	half3  bitangent;
	half3  normal;
	int    diffuseTextureIndex;
	int    normalTextureIndex;
};

struct DescriptorDefinedVertex
{
	float4  position    [[attribute(VertexAttributePosition)]];
	float2  tex_coord   [[attribute(VertexAttributeTexcoord)]];
	half4   normal      [[attribute(VertexAttributeNormal)]];
	half4   tangent     [[attribute(VertexAttributeTangent)]];
	half4   bitangent   [[attribute(VertexAttributeBitangent)]];
};

vertex ColorInOut gbuffer_vertex(DescriptorDefinedVertex  	in        	[[stage_in]],
								 uint 						vertexID  	[[vertex_id]],
                     constant    Vertex* 			        vertexData  [[buffer(BufferIndexVertexData)]],
                     constant    FrameData&		            frameData 	[[buffer(BufferIndexFrameData)]]) {
	
	ColorInOut out;

	// Convert model position to eye space and project to clip space
	float4 model_position = in.position;
	float4 eye_position = frameData.scene_modelview_matrix * model_position;
	out.position = frameData.projection_matrix * eye_position;
	out.tex_coord = in.tex_coord;

	#if USE_EYE_DEPTH
	out.eye_position = eye_position.xyz;
	#endif

	// Rotate tangents, bitangents, and normals by the normal matrix
	half3x3 normalMatrix = half3x3(frameData.scene_normal_matrix);

	// Transform normal, tangent, and bitangent to eye space
	out.tangent = normalize(normalMatrix * in.tangent.xyz);
	out.bitangent = -normalize(normalMatrix * in.bitangent.xyz); // Note the inversion if required
	out.normal = normalize(normalMatrix * in.normal.xyz);
	
	out.diffuseTextureIndex = vertexData[vertexID].diffuseTextureIndex;
	out.normalTextureIndex = vertexData[vertexID].normalTextureIndex;

	return out;
}

float linearDepth(float depth, float near, float far) {
    float z = depth * 2.0f - 1.0f;
    return (2.0f * near * far) / (far + near - z * (far - near));
}

fragment GBufferData gbuffer_fragment(ColorInOut            in                  [[stage_in]],
                          constant    FrameData&            frameData           [[buffer(BufferIndexFrameData)]],
									  texture2d_array<half> baseColorMap        [[texture(TextureIndexBaseColor)]],
									  texture2d_array<half> normalMap           [[texture(TextureIndexNormal)]],
                          constant    TextureInfo*          diffuseTextureInfos [[buffer(BufferIndexDiffuseInfo)]],
                          constant    TextureInfo*          normalTextureInfos  [[buffer(BufferIndexNormalInfo)]]) {

	constexpr sampler linearSampler(mip_filter::linear,
									mag_filter::linear,
									min_filter::linear,
									address::repeat);

	// Sample the base color from the diffuse texture array
	half4 base_color_sample;
	if (in.diffuseTextureIndex >= 0 && (uint)in.diffuseTextureIndex < baseColorMap.get_array_size()) {
		int idx = in.diffuseTextureIndex;
		float2 transformedUV = in.tex_coord *
			(float2(diffuseTextureInfos[idx].width, diffuseTextureInfos[idx].height) /
			 float2(baseColorMap.get_width(0), baseColorMap.get_height(0)));

		base_color_sample = baseColorMap.sample(linearSampler, transformedUV, in.diffuseTextureIndex);
	} else {
		base_color_sample = half4(0.9608, 0.9608, 0.8627, 1.0); // Default color if no texture
	}

	// Sample the normal from the normal map texture array
	half3 eye_normal = normalize(in.normal.xyz); // Default normal
	if (in.normalTextureIndex >= 0 && (uint)in.normalTextureIndex < normalMap.get_array_size()) {
		int idx = in.normalTextureIndex;
		float2 transformedUV = in.tex_coord *
			(float2(normalTextureInfos[idx].width, normalTextureInfos[idx].height) /
			 float2(normalMap.get_width(0), normalMap.get_height(0)));

		half4 normal_sample = normalMap.sample(linearSampler, transformedUV, in.normalTextureIndex);

		// Calculate the tangent-space normal, and transform it to eye space
		half3 tangent_normal = normalize((normal_sample.xyz * 2.0) - 1.0);
		half3 T = normalize(in.tangent.xyz);
		half3 B = normalize(in.bitangent.xyz);
		eye_normal = normalize(tangent_normal.x * T + tangent_normal.y * B + tangent_normal.z * in.normal.xyz);
	}

	// Prepare GBuffer output
	GBufferData gBuffer;
	gBuffer.albedo_specular = base_color_sample; // Albedo (RGB) + Specular (A) if needed
	gBuffer.normal_map = half4(eye_normal, 1.0f);

    float P22 = frameData.projection_matrix[2][2];
    float P23 = frameData.projection_matrix[2][3];
    float near = P23 / (P22 - 1.0);
    float far = P23 / (P22 + 1.0);
    
#if USE_EYE_DEPTH
	gBuffer.depth = in.eye_position.z;
    // Compute Linear Depth
#elif USE_REVERSE_Z
    gBuffer.depth = near / (in.position.z * (far - near) + near);
#else
    gBuffer.depth = linearDepth(in.position.z, near, far);
#endif

	return gBuffer;
}

