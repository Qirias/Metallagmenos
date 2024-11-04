#pragma once
#include "pch.hpp"
#include "mesh.hpp"
#include "textureArray.hpp"
#include <tinyGLTF/tiny_gltf.h>

class GLTFLoader {
public:
    struct ProcessedMeshData {
        std::vector<Vertex> vertices;
        std::vector<uint32_t> indices;
    };
    
    struct GLTFMaterial {
		NS::SharedPtr<MTL::Texture> baseColorTexture;
		NS::SharedPtr<MTL::Texture> metallicRoughnessTexture;
		NS::SharedPtr<MTL::Texture> normalTexture;
		NS::SharedPtr<MTL::Texture> emissiveTexture;
        
        // PBR material properties
        simd::float4 baseColorFactor = {1.0f, 1.0f, 1.0f, 1.0f};
        float metallicFactor = 1.0f;
        float roughnessFactor = 1.0f;
        simd::float3 emissiveFactor = {0.0f, 0.0f, 0.0f};
    };

    struct GLTFModel {
        std::vector<Vertex> 						vertices;
        std::vector<uint32_t> 						indices;
        std::vector<GLTFMaterial> 					materials;
        std::vector<NS::SharedPtr<MTL::Texture>> 	textures;
		MTL::Texture* 								diffuseTextureArray;
        std::vector<Mesh> 							meshes;
		std::vector<TextureInfo> 					diffuseTextureInfos;
    };

    GLTFLoader(MTL::Device* device);
    
    GLTFModel loadModel(const std::string& filepath);

private:
    MTL::Device* _device;
    
	ProcessedMeshData processMesh(const tinygltf::Model& model,
								  const tinygltf::Mesh& mesh,
								  const tinygltf::Primitive& primitive);

                    
    GLTFMaterial processMaterial(const tinygltf::Model& model,
                                const tinygltf::Material& material);
                                
    NS::SharedPtr<MTL::Texture> loadTexture(const tinygltf::Model& model,
                                           const tinygltf::Texture& texture);

    static bool LoadImageData(tinygltf::Image* image, const int imageIndex,
                            std::string* error, std::string* warning, 
                            int req_width, int req_height,
                            const unsigned char* bytes, int size, void* userData);
};
