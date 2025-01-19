#pragma once
#include <simd/simd.h>

using namespace simd;

struct Vertex {
	simd::float4 position;
	simd::float4 normal;
	simd::float4 tangent;
	simd::float4 bitangent;
	simd::float2 textureCoordinate;
	int32_t diffuseTextureIndex;
	int32_t normalTextureIndex;
};

struct TextureInfo {
    int width;
    int height;
};

struct VertexData {
    float4 position;
    float4 normal;
};

struct TransformationData {
    float4x4 translationMatrix;
    float4x4 perspectiveMatrix;
};

struct DebugLineVertex {
    float4 position;
    float4 color;
};
