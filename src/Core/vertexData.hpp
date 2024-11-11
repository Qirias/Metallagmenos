#pragma once
#include <simd/simd.h>

using namespace simd;

struct Vertex {
    float4 position;
    float4 normal;
    float2 textureCoordinate;
    int diffuseTextureIndex;
	int normalTextureIndex;
    float2 padding;
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
