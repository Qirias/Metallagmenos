//
//  TextureArray.hpp
//  Metal-Tutorial
//

#pragma once

#include <simd/simd.h>
using namespace simd;

#include <vector>
#include <string>

#include <tinyobjloader/tiny_obj_loader.h>

#include "camera.hpp"
#include "vertexData.hpp"
#include "textureArray.hpp"

inline bool operator==(const Vertex& lhs, const Vertex& rhs) {
    return lhs.position.x == rhs.position.x &&
           lhs.position.y == rhs.position.y &&
           lhs.position.z == rhs.position.z &&
           lhs.normal.x == rhs.normal.x &&
           lhs.normal.y == rhs.normal.y &&
           lhs.normal.z == rhs.normal.z &&
           lhs.textureCoordinate.x == rhs.textureCoordinate.x &&
           lhs.textureCoordinate.y == rhs.textureCoordinate.y &&
    lhs.diffuseTextureIndex == rhs.diffuseTextureIndex;
}

namespace std {
    template<> struct hash<simd::float3> {
        size_t operator()(simd::float3 const& vector) const {
            size_t h1 = hash<float>{}(vector.x);
            size_t h2 = hash<float>{}(vector.y);
            size_t h3 = hash<float>{}(vector.z);
            return h1 ^ (h2 << 1) ^ (h3 << 2);
        }
    };

    template<> struct hash<simd::float2> {
        size_t operator()(simd::float2 const& vector) const {
            size_t h1 = hash<float>{}(vector.x);
            size_t h2 = hash<float>{}(vector.y);
            return h1 ^ (h2 << 1);
        }
    };

    template<> struct hash<Vertex> {
        size_t operator()(Vertex const& vertex) const {
            size_t h1 = hash<float3>{}(vertex.position.xyz);
            size_t h2 = hash<float3>{}(vertex.normal.xyz);
            size_t h3 = hash<float2>{}(vertex.textureCoordinate);
            size_t h4 = hash<int>{}(vertex.diffuseTextureIndex);
            
            return h1 ^ (h2 << 1) ^ (h3 << 2) ^ (h4 << 3);
        }
    };
}

struct Mesh {
    Mesh(std::string filePath, MTL::Device* metalDevice, MTL::VertexDescriptor* vertexDescriptor, const MeshInfo info);
    Mesh(MTL::Device* device, const Vertex* vertexData, size_t vertexCount, const uint32_t* indexData, size_t indexCount, const MeshInfo info);

    ~Mesh();
    
    bool meshHasTextures() const { return meshInfo.hasTextures; }

public:
    void loadObj(std::string filePath);
    void calculateTangentSpace(std::vector<Vertex>& vertices, const std::vector<uint32_t>& indices);
    void createBuffers(MTL::VertexDescriptor* vertexDescriptor);
    void defaultVertexAttributes();
    
    std::vector<Vertex>                     vertices;
    std::vector<uint32_t>                   vertexIndices;
    TextureArray*                           diffuseTexturesArray;
    TextureArray*                           normalTexturesArray;
    std::unordered_map<Vertex, uint32_t>    vertexMap;
    
    matrix_float4x4 getTransformMatrix() const {
        // Create scaling matrix
        matrix_float4x4 scaleMatrix{simd::float4{meshInfo.scale.x, 0.0f, 0.0f, 0.0f},
                                    simd::float4{0.0f, meshInfo.scale.y, 0.0f, 0.0f},
                                    simd::float4{0.0f, 0.0f, meshInfo.scale.z, 0.0f},
                                    simd::float4{0.0f, 0.0f, 0.0f, 1.0f}};
        
        float cosX = cos(radians_from_degrees(meshInfo.rotation.x));
        float sinX = sin(radians_from_degrees(meshInfo.rotation.x));
        float cosY = cos(radians_from_degrees(meshInfo.rotation.y));
        float sinY = sin(radians_from_degrees(meshInfo.rotation.y));
        float cosZ = cos(radians_from_degrees(meshInfo.rotation.z));
        float sinZ = sin(radians_from_degrees(meshInfo.rotation.z));
        
        // Rotation around X axis
        matrix_float4x4 rotX{simd::float4{1.0f, 0.0f, 0.0f, 0.0f},
                             simd::float4{0.0f, cosX, sinX, 0.0f},
                             simd::float4{0.0f, -sinX, cosX, 0.0f},
                             simd::float4{0.0f, 0.0f, 0.0f, 1.0f}};
        
        // Rotation around Y axis
        matrix_float4x4 rotY{simd::float4{cosY, 0.0f, -sinY, 0.0f},
                             simd::float4{0.0f, 1.0f, 0.0f, 0.0f},
                             simd::float4{sinY, 0.0f, cosY, 0.0f},
                             simd::float4{0.0f, 0.0f, 0.0f, 1.0f}};
        
        // Rotation around Z axis
        matrix_float4x4 rotZ{simd::float4{cosZ, sinZ, 0.0f, 0.0f},
                             simd::float4{-sinZ, cosZ, 0.0f, 0.0f},
                             simd::float4{0.0f, 0.0f, 1.0f, 0.0f},
                             simd::float4{0.0f, 0.0f, 0.0f, 1.0f}};
        
        // First Z, then Y, then X
        matrix_float4x4 rotationMatrix = matrix_multiply(matrix_multiply(rotZ, rotY), rotX);
        
        matrix_float4x4 posMatrix{simd::float4{1.0f, 0.0f, 0.0f, 0.0f},
                                  simd::float4{0.0f, 1.0f, 0.0f, 0.0f},
                                  simd::float4{0.0f, 0.0f, 1.0f, 0.0f},
                                  simd::float4{meshInfo.position.x, meshInfo.position.y, meshInfo.position.z, 1.0f}};
        

        matrix_float4x4 rotateScale = matrix_multiply(rotationMatrix, scaleMatrix);
        return matrix_multiply(posMatrix, rotateScale);
    }
    
public:
    MTL::Device*    device;
    MTL::Buffer*    vertexBuffer;
    MTL::Buffer*    indexBuffer;
    unsigned long   indexCount;
    unsigned long   triangleCount;
    bool            hasTextures;
    
    MTL::Texture*   diffuseTextures;
    MTL::Texture*   normalTextures;
    MTL::Buffer*    diffuseTextureInfos;
    MTL::Buffer*    normalTextureInfos;
    
    MeshInfo        meshInfo;
};
