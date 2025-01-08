#define METAL
#include <metal_stdlib>
using namespace metal;

#include "vertexData.hpp"
#include "shaderTypes.hpp"

struct OutData {
	float4 position [[position]];
	float4 normal;
	float4 tangent;
	float4 bitangent;
	float4 fragmentPosition;
	float2 textureCoordinate;
	int diffuseTextureIndex;
	int normalTextureIndex;
};

bool operator==(const device Vertex& a, const device Vertex& b) {
	return all(a.position == b.position) &&
		   all(a.normal == b.normal) &&
		   all(a.tangent == b.tangent) &&
		   all(a.bitangent == b.bitangent) &&
		   all(a.textureCoordinate == b.textureCoordinate) &&
		   a.diffuseTextureIndex == b.diffuseTextureIndex &&
		   a.normalTextureIndex == b.normalTextureIndex;
}

struct Mesh {
	constant Vertex* vertices;
};

float3 applyNormalMap(float3 N, float3 T, float3 B, float2 texcoord,
					 texture2d_array<float> normalMap,
					 int normalMapIndex, sampler textureSampler) {
	float4 normalSample = normalMap.sample(textureSampler, texcoord, normalMapIndex);
	float3 tangentNormal = normalSample.xyz * 2.0 - 1.0;
	
	float3x3 TBN = float3x3(T, B, N);
	return normalize(TBN * tangentNormal);
}

vertex OutData vertexShader(
			 uint vertexID [[vertex_id]],
			 constant Vertex* vertexData,
			 constant float4x4& modelMatrix,
			 constant FrameData& frameData [[buffer(2)]]) {
	OutData out;
	constant Vertex& vert = vertexData[vertexID];
	
	out.position = frameData.projection_matrix * frameData.view_matrix * modelMatrix * float4(vert.position.xyz, 1.0f);
	out.normal = modelMatrix * float4(vert.normal.xyz, 0.0f);
	out.tangent = modelMatrix * float4(vert.tangent.xyz, 0.0f);
	out.bitangent = modelMatrix * float4(vert.bitangent.xyz, 0.0f);
	out.fragmentPosition = modelMatrix * float4(vert.position.xyz, 1.0f);
	out.textureCoordinate = vert.textureCoordinate;
	out.diffuseTextureIndex = vert.diffuseTextureIndex;
	out.normalTextureIndex = vert.normalTextureIndex;
	return out;
}

fragment float4 fragmentShader(OutData in [[stage_in]],
							 constant FrameData& frameData [[ buffer(0) ]],
							 texture2d_array<float> diffuseTextures [[texture(1)]],
							 texture2d_array<float> normalTextures [[texture(2)]],
							 constant TextureInfo* diffuseTextureInfos [[buffer(3)]],
							 constant TextureInfo* normalTextureInfos [[buffer(4)]]) {
	
	constexpr sampler textureSampler(
		mag_filter::linear,
		min_filter::linear,
		mip_filter::linear,
		address::repeat,
		s_address::repeat,
		t_address::repeat
	);
	
	// Get base color
	float4 baseColor;
	if (in.diffuseTextureIndex >= 0 && (uint)in.diffuseTextureIndex < diffuseTextures.get_array_size()) {
		int idx = in.diffuseTextureIndex;
		float2 transformedUV = in.textureCoordinate *
			(float2(diffuseTextureInfos[idx].width, diffuseTextureInfos[idx].height) /
			 float2(diffuseTextures.get_width(0), diffuseTextures.get_height(0)));
		
		baseColor = diffuseTextures.sample(textureSampler, transformedUV, in.diffuseTextureIndex);
		if (baseColor.a < 0.01) {
			discard_fragment();
		}
	} else {
		baseColor = float4(0.9608, 0.9608, 0.8627, 1.0);
	}
	
	// Calculate normal from normal map using precalculated tangent space
	float3 N = normalize(in.normal.xyz);
	if (in.normalTextureIndex >= 0 && (uint)in.normalTextureIndex < normalTextures.get_array_size()) {
		int idx = in.normalTextureIndex;
		float2 transformedUV = in.textureCoordinate *
			(float2(normalTextureInfos[idx].width, normalTextureInfos[idx].height) /
			 float2(normalTextures.get_width(0), normalTextures.get_height(0)));
		
		float3 T = normalize(in.tangent.xyz);
		float3 B = normalize(in.bitangent.xyz);
		N = applyNormalMap(N, T, B, transformedUV, normalTextures, in.normalTextureIndex, textureSampler);
	}
	
	// Lighting calculations with the normal
	float3 L = normalize(frameData.sun_eye_direction.xyz);
	float3 V = normalize(in.fragmentPosition.xyz);
	float3 R = reflect(-L, N);
	
	float3 ambient = 0.2 * frameData.sun_color.rgb;
	float diff = max(dot(N, L), 0.0);
	float3 diffuse = diff * frameData.sun_color.rgb;
	
	float spec = pow(max(dot(V, R), 0.0), 32.0);
	float3 specular = 0.5 * spec * frameData.sun_color.rgb;
	
	float3 finalColor = (ambient + diffuse + specular) * baseColor.rgb;
	
	return float4(finalColor, baseColor.a);
}
