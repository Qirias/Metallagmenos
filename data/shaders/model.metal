#define METAL
#include <metal_stdlib>
using namespace metal;

#include "vertexData.hpp"

struct OutData {
    // The [[position]] attribute of this member indicates that this value
    // is the clip space position of the vertex when this structure is
    // returned from the vertex function.
    float4 position [[position]];
    float4 normal;
    float4 fragmentPosition;
    float2 textureCoordinate;
    int diffuseTextureIndex;
	int normalTextureIndex;
};

struct Mesh {
    constant Vertex* vertices;
};

float3 perturbNormal(float3 N, float3 V, float2 texcoord, texture2d_array<float> normalMap,
					int normalMapIndex, sampler textureSampler) {
	// Sample the normal map and convert from [0,1] to [-1,1] range
	float4 normalSample = normalMap.sample(textureSampler, texcoord, normalMapIndex);
	float3 tangentNormal = normalSample.xyz * 2.0 - 1.0;
	
	// Calculate tangent and bitangent vectors
	float3 Q1 = dfdx(V);
	float3 Q2 = dfdy(V);
	float2 st1 = dfdx(texcoord);
	float2 st2 = dfdy(texcoord);
	
	float3 T = normalize(Q1 * st2.y - Q2 * st1.y);
	float3 B = normalize(Q2 * st1.x - Q1 * st2.x);
	
	float3x3 TBN = float3x3(T, B, N);
	
	return normalize(TBN * tangentNormal);
}

vertex OutData vertexShader(
             uint vertexID [[vertex_id]],
             constant Vertex* vertexData,
             constant float4x4& modelMatrix,
             constant float4x4& viewMatrix,
             constant float4x4& perspectiveMatrix)
{
    OutData out;
    out.position = perspectiveMatrix * viewMatrix * modelMatrix * float4(vertexData[vertexID].position.xyz, 1.0f);
    out.normal = modelMatrix * float4(vertexData[vertexID].normal.xyz, 0.0f);
    out.fragmentPosition = modelMatrix * float4(vertexData[vertexID].position.xyz, 1.0f);
    out.textureCoordinate = vertexData[vertexID].textureCoordinate;
    out.diffuseTextureIndex = vertexData[vertexID].diffuseTextureIndex;
	out.normalTextureIndex = vertexData[vertexID].normalTextureIndex;
    return out;
}


fragment float4 fragmentShader(OutData in [[stage_in]],
							 constant float4& cubeColor [[buffer(0)]],
							 constant float4& lightColor [[buffer(1)]],
							 constant float4& lightPosition [[buffer(2)]],
							 texture2d_array<float> diffuseTextures [[texture(3)]],
							 texture2d_array<float> normalTextures [[texture(4)]],
							 constant TextureInfo* diffuseTextureInfos [[buffer(5)]],
							 constant TextureInfo* normalTextureInfos [[buffer(6)]]) {
	
	constexpr sampler textureSampler(
		mag_filter::linear,
		min_filter::linear,
		mip_filter::linear,  // Add mip filtering if you have mipmaps
		address::repeat,     // This makes the texture repeat instead of stretch
		s_address::repeat,   // Explicit repeat for s coordinate
		t_address::repeat    // Explicit repeat for t coordinate
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
		baseColor = float4(0.9608, 0.9608, 0.8627, 1.0); // Beige default for surfaces without diffuse texture
	}
	
	
	// Calculate normal from normal map if available
	float3 N = normalize(in.normal.xyz);
	if (in.normalTextureIndex >= 0 && (uint)in.normalTextureIndex < normalTextures.get_array_size()) {
		int idx = in.normalTextureIndex;
		float2 transformedUV = in.textureCoordinate *
			(float2(normalTextureInfos[idx].width, normalTextureInfos[idx].height) /
			 float2(normalTextures.get_width(0), normalTextures.get_height(0)));
		
		float3 V = normalize(in.fragmentPosition.xyz);
		N = perturbNormal(N, V, transformedUV, normalTextures, in.normalTextureIndex, textureSampler);
	}
	
	// Lighting calculations with the new normal
	float3 L = normalize(lightPosition.xyz);
	float3 V = normalize(in.fragmentPosition.xyz);
	float3 R = reflect(-L, N);
	
	float3 ambient = 0.2 * lightColor.rgb;
	
	float diff = max(dot(N, L), 0.0);
	float3 diffuse = diff * lightColor.rgb;
	
	float spec = pow(max(dot(V, R), 0.0), 32.0);
	float3 specular = 0.5 * spec * lightColor.rgb;
	
	float3 finalColor = (ambient + diffuse + specular) * baseColor.rgb;
	
	return float4(finalColor, baseColor.a);
}
