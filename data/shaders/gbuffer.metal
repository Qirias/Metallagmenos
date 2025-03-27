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

constant bool hasTextures [[function_constant(0)]];
constant bool isEmissive [[function_constant(1)]];

struct DescriptorDefinedVertex
{
    float4  position    [[attribute(VertexAttributePosition)]];
    half4   normal      [[attribute(VertexAttributeNormal)]];
    float2  tex_coord   [[attribute(VertexAttributeTexcoord), function_constant(hasTextures)]];
    half4   tangent     [[attribute(VertexAttributeTangent), function_constant(hasTextures)]];
    half4   bitangent   [[attribute(VertexAttributeBitangent), function_constant(hasTextures)]];
};

vertex ColorInOut gbuffer_vertex(DescriptorDefinedVertex  	in        	[[stage_in]],
								 uint 						vertexID  	[[vertex_id]],
                     constant    Vertex* 			        vertexData  [[buffer(BufferIndexVertexData)]],
                     constant    FrameData&		            frameData 	[[buffer(BufferIndexFrameData)]],
                     constant    float4x4&                  modelMatrix [[buffer(BufferIndexVertexBytes)]]) {
	
    ColorInOut out;

    // Convert model position to eye space and project to clip space
    float4 model_position = modelMatrix * in.position;
    float4 eye_position = frameData.scene_modelview_matrix * model_position;
    out.position = frameData.projection_matrix * eye_position;

    // Set default values for when textures are disabled
    out.tex_coord = hasTextures ? in.tex_coord : float2(0, 0);
    out.diffuseTextureIndex = hasTextures ? vertexData[vertexID].diffuseTextureIndex : -1;
    out.normalTextureIndex = hasTextures ? vertexData[vertexID].normalTextureIndex : -1;

    #if USE_EYE_DEPTH
    out.eye_position = eye_position.xyz;
    #endif

    // Rotate normals by the normal matrix
    half3x3 normalMatrix = half3x3(frameData.scene_normal_matrix);

    out.normal = normalize(normalMatrix * in.normal.xyz);

    if (hasTextures) {
        out.tangent = normalize(normalMatrix * in.tangent.xyz);
        out.bitangent = -normalize(normalMatrix * in.bitangent.xyz);
    } else {
        out.tangent = half3(1, 0, 0);
        out.bitangent = half3(0, 1, 0);
    }

    return out;
}

float linearDepth(float depth, float near, float far) {
    float z = depth * 2.0f - 1.0f;
    return (2.0f * near * far) / (far + near - z * (far - near));
}

fragment GBufferData gbuffer_fragment(ColorInOut            in                  [[stage_in]],
                          constant    FrameData&            frameData           [[buffer(BufferIndexFrameData)]],
						  constant    bool&                 isEmissive          [[buffer(BufferIndexIsEmissive)]],
						  constant    float3&               emissiveColor       [[buffer(BufferIndexEmissiveColor)]],
									  texture2d_array<half> baseColorMap        [[texture(TextureIndexBaseColor),   function_constant(hasTextures)]],
									  texture2d_array<half> normalMap           [[texture(TextureIndexNormal),      function_constant(hasTextures)]],
                          constant    TextureInfo*          diffuseTextureInfos [[buffer(BufferIndexDiffuseInfo),   function_constant(hasTextures)]],
                          constant    TextureInfo*          normalTextureInfos  [[buffer(BufferIndexNormalInfo),    function_constant(hasTextures)]]) {

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
	if (hasTextures && in.normalTextureIndex >= 0 && (uint)in.normalTextureIndex < normalMap.get_array_size()) {
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
	gBuffer.normal_map = half4(eye_normal, 1.0f);

	if (!hasTextures) {
		gBuffer.albedo_specular = isEmissive ? half4(half3(emissiveColor), 1.0h) : base_color_sample;
	} else {
		gBuffer.albedo_specular = half4(base_color_sample.rgb, 1.0); // Albedo (RGB) + Specular (A)
	}

	gBuffer.normal_map.a = (isEmissive) ? -1 : 1; // Store emissive flag in the alpha channel

    
    float near = frameData.near_plane;
    float far = frameData.far_plane;
    
#if USE_EYE_DEPTH
	gBuffer.depth = in.eye_position.z;
#elif USE_REVERSE_Z
    gBuffer.depth = near / (in.position.z * (far - near) + near);
#else
    gBuffer.depth = linearDepth(in.position.z, near, far);
#endif

	return gBuffer;
}

