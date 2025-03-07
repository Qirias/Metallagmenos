#include "mesh.hpp"
#include "../../data/shaders/shaderTypes.hpp"

#include <iostream>
#include <unordered_map>
#include <string>

// For tinyobjloader
Mesh::Mesh(std::string filePath, MTL::Device* metalDevice, MTL::VertexDescriptor* vertexDescriptor, const MeshInfo info) {
    device = metalDevice;
    meshInfo = info;
    
    loadObj(filePath);
    createBuffers(vertexDescriptor);
}

// For tinyGLTF
Mesh::Mesh(MTL::Device* device, const Vertex* vertexData, size_t vertexCount, const uint32_t* indexData, size_t indexCount, const MeshInfo info)
: device(device) {
    meshInfo.scale = info.scale;
    meshInfo.position = info.position;
    meshInfo.hasTextures = info.hasTextures;
    
    // Create vertex buffer with proper alignment
    size_t vertexBufferSize = vertexCount * sizeof(Vertex);
    
    vertexBuffer = device->newBuffer(vertexData, vertexBufferSize, MTL::ResourceStorageModeShared);
    vertexBuffer->setLabel(NS::String::string("Mesh Vertex Buffer", NS::ASCIIStringEncoding));

    // Create index buffer
    this->indexCount = indexCount;
    indexBuffer = device->newBuffer(indexData, indexCount * sizeof(uint32_t), MTL::ResourceStorageModeShared);
    indexBuffer->setLabel(NS::String::string("Mesh Index Buffer", NS::ASCIIStringEncoding));
}

Mesh::~Mesh() {
    if (meshInfo.hasTextures) {
        normalTextures->release();
        normalTextureInfos->release();
        diffuseTextures->release();
        diffuseTextureInfos->release();
    }
    vertexBuffer->release();
    indexBuffer->release();
}

void Mesh::loadObj(std::string filePath) {
    tinyobj::attrib_t vertexArrays;
    std::vector<tinyobj::shape_t> shapes;
    std::vector<tinyobj::material_t> materials;
    
    std::string baseDirectory = filePath.substr(0, filePath.find_last_of("/\\") + 1);
    std::string warning;
    std::string error;
    
    bool ret = tinyobj::LoadObj(&vertexArrays, &shapes, &materials, &error,
                                filePath.c_str(), baseDirectory.c_str(), true);
    
    // Create texture mappings for both diffuse and normal textures
    std::unordered_map<std::string, int> diffuseTextureIndexMap;
    std::unordered_map<std::string, int> normalTextureIndexMap;
    std::vector<std::string> diffuseFilePaths;
    std::vector<std::string> normalFilePaths;
    
    if (meshInfo.hasTextures) {
        std::cout << "Loading Textures..." << std::endl;
        // First pass: collect all textures
        for (const auto& material : materials) {
            // Handle diffuse textures
            if (!material.diffuse_texname.empty()) {
                std::string texturePath = baseDirectory + material.diffuse_texname;
                std::replace(texturePath.begin(), texturePath.end(), '\\', '/');
                
                if (diffuseTextureIndexMap.find(material.diffuse_texname) == diffuseTextureIndexMap.end()) {
                    int textureIndex = static_cast<int>(diffuseFilePaths.size());
                    diffuseTextureIndexMap[material.diffuse_texname] = textureIndex;
                    diffuseFilePaths.push_back(texturePath);
                }
            }
            
            // Handle normal textures (both bump and normal map)
            std::string normalTexName = material.normal_texname;
            if (normalTexName.empty()) {
                normalTexName = material.bump_texname; // Use bump map if normal map isn't specified
            }
            
            if (!normalTexName.empty()) {
                std::string texturePath = baseDirectory + normalTexName;
                std::replace(texturePath.begin(), texturePath.end(), '\\', '/');
                
                if (normalTextureIndexMap.find(normalTexName) == normalTextureIndexMap.end()) {
                    int textureIndex = static_cast<int>(normalFilePaths.size());
                    normalTextureIndexMap[normalTexName] = textureIndex;
                    normalFilePaths.push_back(texturePath);
//                    std::cout << "Normal Texture " << textureIndex << ": " << texturePath << std::endl;
                }
            }
        }
        
        // Create texture arrays
        diffuseTexturesArray = new TextureArray(diffuseFilePaths, device, TextureType::DIFFUSE);
        normalTexturesArray = new TextureArray(normalFilePaths, device, TextureType::NORMAL);
    }
    
    // Process geometry
    vertices.clear();
    vertexIndices.clear();
    vertexMap.clear();
    
    for (const auto& shape : shapes) {
        size_t index_offset = 0;
        
        for (size_t f = 0; f < shape.mesh.num_face_vertices.size(); f++) {
            int material_id = -1;
            if (meshInfo.hasTextures) {
                material_id = shape.mesh.material_ids[f];
            }
            
            if (!meshInfo.hasTextures || material_id < 0 || material_id >= materials.size()) {
//                std::cerr << "Invalid material ID: " << material_id << std::endl;
//                continue;
            }
            
            // Get texture indices for both diffuse and normal maps
            int diffuseTextureIndex = -1;
            int normalTextureIndex = -1;
            
            if (meshInfo.hasTextures) {
                const auto& material = materials[material_id];
                
                if (!material.diffuse_texname.empty()) {
                    auto it = diffuseTextureIndexMap.find(material.diffuse_texname);
                    if (it != diffuseTextureIndexMap.end()) {
                        diffuseTextureIndex = it->second;
                    }
                }
                
                std::string normalTexName = material.normal_texname;
                if (normalTexName.empty()) {
                    normalTexName = material.bump_texname;
                }
                
                if (!normalTexName.empty()) {
                    auto it = normalTextureIndexMap.find(normalTexName);
                    if (it != normalTextureIndexMap.end()) {
                        normalTextureIndex = it->second;
                    }
                }
            }
            
            // Process vertices
            int fv = 3;
            for (int v = 0; v < fv; v++) {
                tinyobj::index_t idx = shape.mesh.indices[index_offset + v];
                
                Vertex vertex{};
                
                if (idx.vertex_index >= 0) {
                    vertex.position = {
                        vertexArrays.vertices[3 * idx.vertex_index + 0],
                        vertexArrays.vertices[3 * idx.vertex_index + 1],
                        vertexArrays.vertices[3 * idx.vertex_index + 2],
                        1.0f
                    };
                }
                
                if (idx.normal_index >= 0) {
                    vertex.normal = {
                        vertexArrays.normals[3 * idx.normal_index + 0],
                        vertexArrays.normals[3 * idx.normal_index + 1],
                        vertexArrays.normals[3 * idx.normal_index + 2],
                        0.0f
                    };
                }
                
                if (meshInfo.hasTextures && idx.texcoord_index >= 0) {
                    vertex.textureCoordinate = {
                        vertexArrays.texcoords[2 * idx.texcoord_index + 0],
                        vertexArrays.texcoords[2 * idx.texcoord_index + 1]
                    };
                }
                
                if (meshInfo.hasTextures) {
                    vertex.diffuseTextureIndex = diffuseTextureIndex;
                    vertex.normalTextureIndex = normalTextureIndex;
                }
                
                uint32_t vertexIndex;
                auto vertexIt = vertexMap.find(vertex);
                if (vertexIt == vertexMap.end()) {
                    vertexIndex = static_cast<uint32_t>(vertices.size());
                    vertexMap[vertex] = vertexIndex;
                    vertices.push_back(vertex);
                } else {
                    vertexIndex = vertexIt->second;
                }
                
                vertexIndices.push_back(vertexIndex);
            }
            index_offset += fv;
            triangleCount++;
        }
    }
    
    if (meshInfo.hasTextures) {
        calculateTangentSpace(vertices, vertexIndices);
    }
}

void Mesh::calculateTangentSpace(std::vector<Vertex>& vertices, const std::vector<uint32_t>& indices) {
    for (size_t i = 0; i < indices.size(); i += 3) {
        Vertex& v0 = vertices[indices[i]];
        Vertex& v1 = vertices[indices[i + 1]];
        Vertex& v2 = vertices[indices[i + 2]];

        simd::float3 pos0{v0.position.x, v0.position.y, v0.position.z};
        simd::float3 pos1{v1.position.x, v1.position.y, v1.position.z};
        simd::float3 pos2{v2.position.x, v2.position.y, v2.position.z};

        simd::float2 uv0 = v0.textureCoordinate;
        simd::float2 uv1 = v1.textureCoordinate;
        simd::float2 uv2 = v2.textureCoordinate;

        simd::float3 edge1 = pos1 - pos0;
        simd::float3 edge2 = pos2 - pos0;
        simd::float2 deltaUV1 = uv1 - uv0;
        simd::float2 deltaUV2 = uv2 - uv0;

        float f = 1.0f / (deltaUV1.x * deltaUV2.y - deltaUV2.x * deltaUV1.y);

        simd::float3 tangent;
        tangent.x = f * (deltaUV2.y * edge1.x - deltaUV1.y * edge2.x);
        tangent.y = f * (deltaUV2.y * edge1.y - deltaUV1.y * edge2.y);
        tangent.z = f * (deltaUV2.y * edge1.z - deltaUV1.y * edge2.z);
        tangent = simd::normalize(tangent);

        simd::float3 bitangent;
        bitangent.x = f * (-deltaUV2.x * edge1.x + deltaUV1.x * edge2.x);
        bitangent.y = f * (-deltaUV2.x * edge1.y + deltaUV1.x * edge2.y);
        bitangent.z = f * (-deltaUV2.x * edge1.z + deltaUV1.x * edge2.z);
        bitangent = simd::normalize(bitangent);

        // Assign to all three vertices
        for (int j = 0; j < 3; ++j) {
            Vertex& v = vertices[indices[i + j]];
            v.tangent = simd::float4{tangent.x, tangent.y, tangent.z, 0.0f};
            v.bitangent = simd::float4{bitangent.x, bitangent.y, bitangent.z, 0.0f};
        }
    }
}

void Mesh::createBuffers(MTL::VertexDescriptor* vertexDescriptor) {
    // Check for empty vertices
    if (vertices.empty()) {
        std::cerr << "Error: Cannot create vertex buffer - no vertices loaded" << std::endl;
        return;
    }
    
    // Create Vertex Buffer with safety checks
    unsigned long vertexBufferSize = sizeof(Vertex) * vertices.size();
    if (vertexBufferSize > 0 && vertices.data() != nullptr) {
        vertexBuffer = device->newBuffer(vertices.data(), vertexBufferSize, MTL::ResourceStorageModeShared);
        if (vertexBuffer) {
            vertexBuffer->setLabel(NS::String::string("Mesh Vertex Buffer", NS::ASCIIStringEncoding));
        } else {
            std::cerr << "Error: Failed to create vertex buffer" << std::endl;
        }
    } else {
        std::cerr << "Error: Invalid vertex data or size" << std::endl;
    }
    
    // Check for empty indices
    if (vertexIndices.empty()) {
        std::cerr << "Error: Cannot create index buffer - no indices loaded" << std::endl;
        return;
    }
    
    // Create Index Buffer with safety checks
    indexCount = vertexIndices.size();
    unsigned long indexBufferSize = sizeof(uint32_t) * vertexIndices.size();
    if (indexBufferSize > 0 && vertexIndices.data() != nullptr) {
        indexBuffer = device->newBuffer(vertexIndices.data(), indexBufferSize, MTL::ResourceStorageModeShared);
        if (!indexBuffer) {
            std::cerr << "Error: Failed to create index buffer" << std::endl;
        }
    } else {
        std::cerr << "Error: Invalid index data or size" << std::endl;
    }
    
    // Handle textures only if we have them
    if (meshInfo.hasTextures) {
        // Check diffuse textures
        if (diffuseTexturesArray && diffuseTexturesArray->diffuseTextureArray) {
            diffuseTextures = diffuseTexturesArray->diffuseTextureArray;
            diffuseTextures->setLabel(NS::String::string("Diffuse Texture Array", NS::ASCIIStringEncoding));
            
            // Create Diffuse Texture Info with safety checks
            if (!diffuseTexturesArray->diffuseTextureInfos.empty()) {
                size_t diffuseBufferSize = diffuseTexturesArray->diffuseTextureInfos.size() * sizeof(TextureInfo);
                if (diffuseBufferSize > 0 && diffuseTexturesArray->diffuseTextureInfos.data() != nullptr) {
                    diffuseTextureInfos = device->newBuffer(
                        diffuseTexturesArray->diffuseTextureInfos.data(),
                        diffuseBufferSize,
                        MTL::ResourceStorageModeShared
                    );
                    if (diffuseTextureInfos) {
                        diffuseTextureInfos->setLabel(NS::String::string("Diffuse Texture Info Array", NS::ASCIIStringEncoding));
                    } else {
                        std::cerr << "Error: Failed to create diffuse texture info buffer" << std::endl;
                    }
                } else {
                    std::cerr << "Error: Invalid diffuse texture info data or size" << std::endl;
                }
            } else {
                std::cerr << "Warning: No diffuse texture info data available" << std::endl;
            }
        } else {
            std::cerr << "Warning: No diffuse texture array available" << std::endl;
        }
        
        // Check normal textures
        if (normalTexturesArray && normalTexturesArray->normalTextureArray) {
            normalTextures = normalTexturesArray->normalTextureArray;
            normalTextures->setLabel(NS::String::string("Normal Texture Array", NS::ASCIIStringEncoding));
            
            // Create normal Texture Info with safety checks
            if (!normalTexturesArray->normalTextureInfos.empty()) {
                size_t normalBufferSize = normalTexturesArray->normalTextureInfos.size() * sizeof(TextureInfo);
                if (normalBufferSize > 0 && normalTexturesArray->normalTextureInfos.data() != nullptr) {
                    normalTextureInfos = device->newBuffer(
                        normalTexturesArray->normalTextureInfos.data(),
                        normalBufferSize,
                        MTL::ResourceStorageModeShared
                    );
                    if (normalTextureInfos) {
                        normalTextureInfos->setLabel(NS::String::string("Normal Texture Info Array", NS::ASCIIStringEncoding));
                    } else {
                        std::cerr << "Error: Failed to create normal texture info buffer" << std::endl;
                    }
                } else {
                    std::cerr << "Error: Invalid normal texture info data or size" << std::endl;
                }
            } else {
                std::cerr << "Warning: No normal texture info data available" << std::endl;
            }
        } else {
            std::cerr << "Warning: No normal texture array available" << std::endl;
        }
    }

    // We won't modify the vertex descriptor here anymore
    // The Engine class is now responsible for creating a complete vertex descriptor
    // that works for both textured and non-textured meshes
}

void Mesh::defaultVertexAttributes() {
    // Only needed for non-textured meshes
    if (!meshInfo.hasTextures) {
        for (auto& vertex : vertices) {
            // Set default texture coordinates
            vertex.textureCoordinate = {0.0f, 0.0f};
            
            // Set default tangent and bitangent
            // Calculate a default tangent space from the normal
            float3 n = float3{vertex.normal.x, vertex.normal.y, vertex.normal.z};
            float3 t, b;
            
            // Find a perpendicular vector to use as tangent
            if (std::abs(n.x) > std::abs(n.z)) {
                t = float3{-n.y, n.x, 0.0f};
            } else {
                t = float3{0.0f, -n.z, n.y};
            }
            t = normalize(t);
            
            // Calculate bitangent using cross product
            b = cross(n, t);
            
            // Set the values
            vertex.tangent = {t.x, t.y, t.z, 0.0f};
            vertex.bitangent = {b.x, b.y, b.z, 0.0f};
            
            // Set default texture indices
            vertex.diffuseTextureIndex = -1;
            vertex.normalTextureIndex = -1;
        }
    }
}
