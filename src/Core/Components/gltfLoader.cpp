#include "gltfLoader.hpp"

GLTFLoader::GLTFLoader(MTL::Device* device) : _device(device) {}

GLTFLoader::GLTFModel GLTFLoader::loadModel(const std::string& filepath) {
    tinygltf::Model gltfModel;
    tinygltf::TinyGLTF loader;
    std::string err, warn;
    
    loader.SetImageLoader(LoadImageData, nullptr); // Static function for loading images
    
    bool ret;
    std::string extension = filepath.substr(filepath.find_last_of(".") + 1);
    if (extension == "glb") {
        ret = loader.LoadBinaryFromFile(&gltfModel, &err, &warn, filepath);
    } else {
        ret = loader.LoadASCIIFromFile(&gltfModel, &err, &warn, filepath);
    }
    
    if (!ret) {
        throw std::runtime_error("Failed to load GLTF model: " + err);
    }
    
    GLTFModel model;
    
    // Process each mesh
    for (const auto& mesh : gltfModel.meshes) {
        for (const auto& primitive : mesh.primitives) {
            model.meshes.push_back(processMesh(gltfModel, mesh, primitive));
        }
    }
    
    // Process materials
    for (const auto& material : gltfModel.materials) {
        model.materials.push_back(processMaterial(gltfModel, material));
    }
    
    return model;
}

bool GLTFLoader::LoadImageData(tinygltf::Image* image, const int imageIndex,
                         std::string* error, std::string* warning, 
                         int req_width, int req_height,
                         const unsigned char* bytes, int size, void* userData) {
        
        int width, height, channels;
        unsigned char* data = stbi_load_from_memory(bytes, size, &width, &height, 
                                                &channels, STBI_rgb_alpha);
        
        if (!data) {
            if (error) {
                *error = "Failed to load image: " + std::string(stbi_failure_reason());
            }
            return false;
        }
        
        image->width = width;
        image->height = height;
        image->component = 4;
        image->bits = 8;
        image->pixel_type = TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE;
        
        image->image.resize(width * height * 4);
        std::memcpy(image->image.data(), data, width * height * 4);
        
        stbi_image_free(data);
        
        return true;
    }

Mesh GLTFLoader::processMesh(const tinygltf::Model& model, 
                             const tinygltf::Mesh& mesh,
                             const tinygltf::Primitive& primitive) {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
    
    // Get buffer data for positions
    const float* positions = nullptr;
    const float* normals = nullptr;
    const float* texCoords = nullptr;
    size_t vertexCount = 0;
    
    // Get attribute accessors
    if (primitive.attributes.find("POSITION") != primitive.attributes.end()) {
        const tinygltf::Accessor& accessor = 
            model.accessors[primitive.attributes.at("POSITION")];
        const tinygltf::BufferView& view = model.bufferViews[accessor.bufferView];
        positions = reinterpret_cast<const float*>(&model.buffers[view.buffer]
            .data[accessor.byteOffset + view.byteOffset]);
        vertexCount = accessor.count;
    }
    
    if (primitive.attributes.find("NORMAL") != primitive.attributes.end()) {
        const tinygltf::Accessor& accessor = 
            model.accessors[primitive.attributes.at("NORMAL")];
        const tinygltf::BufferView& view = model.bufferViews[accessor.bufferView];
        normals = reinterpret_cast<const float*>(&model.buffers[view.buffer]
            .data[accessor.byteOffset + view.byteOffset]);
    }
    
    if (primitive.attributes.find("TEXCOORD_0") != primitive.attributes.end()) {
        const tinygltf::Accessor& accessor = 
            model.accessors[primitive.attributes.at("TEXCOORD_0")];
        const tinygltf::BufferView& view = model.bufferViews[accessor.bufferView];
        texCoords = reinterpret_cast<const float*>(&model.buffers[view.buffer]
            .data[accessor.byteOffset + view.byteOffset]);
    }
    
    // Build vertex data
    for (size_t i = 0; i < vertexCount; i++) {
        Vertex vertex;
        
        if (positions) {
            vertex.position = {
                positions[i * 3 + 0],
                positions[i * 3 + 1],
                positions[i * 3 + 2]
            };
        }
        
        if (normals) {
            vertex.normal = {
                normals[i * 3 + 0],
                normals[i * 3 + 1],
                normals[i * 3 + 2]
            };
        }
        
        if (texCoords) {
            vertex.textureCoordinate = {
                texCoords[i * 2 + 0],
                texCoords[i * 2 + 1]
            };
        }
        // vertex.diffuseTextureIndex = primitive.material;
        vertices.push_back(vertex);
    }
    
    // Get indices
    if (primitive.indices >= 0) {
        const tinygltf::Accessor& accessor = model.accessors[primitive.indices];
        const tinygltf::BufferView& view = model.bufferViews[accessor.bufferView];
        const uint8_t* data = &model.buffers[view.buffer]
            .data[accessor.byteOffset + view.byteOffset];
        
        switch (accessor.componentType) {
            case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT: {
                const uint16_t* indices16 = reinterpret_cast<const uint16_t*>(data);
                for (size_t i = 0; i < accessor.count; i++) {
                    indices.push_back(static_cast<uint32_t>(indices16[i]));
                }
                break;
            }
            case TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT: {
                const uint32_t* indices32 = reinterpret_cast<const uint32_t*>(data);
                for (size_t i = 0; i < accessor.count; i++) {
                    indices.push_back(indices32[i]);
                }
                break;
            }
        }
    }
    
    return Mesh(_device, vertices.data(), vertices.size(), indices.data(), indices.size());
}

GLTFLoader::GLTFMaterial GLTFLoader::processMaterial(
    const tinygltf::Model& model,
    const tinygltf::Material& material) {
    
    GLTFMaterial result;
    
    // Process PBR Metallic Roughness
    if (material.pbrMetallicRoughness.baseColorTexture.index >= 0) {
        const auto& texture = model.textures[
            material.pbrMetallicRoughness.baseColorTexture.index];
        result.baseColorTexture = loadTexture(model, texture);
    }
    
    if (material.pbrMetallicRoughness.metallicRoughnessTexture.index >= 0) {
        const auto& texture = model.textures[
            material.pbrMetallicRoughness.metallicRoughnessTexture.index];
        result.metallicRoughnessTexture = loadTexture(model, texture);
    }
    
    // Normal map
    if (material.normalTexture.index >= 0) {
        const auto& texture = model.textures[material.normalTexture.index];
        result.normalTexture = loadTexture(model, texture);
    }
    
    // Emissive map
    if (material.emissiveTexture.index >= 0) {
        const auto& texture = model.textures[material.emissiveTexture.index];
        result.emissiveTexture = loadTexture(model, texture);
    }
    
    // Material factors
    if (!material.pbrMetallicRoughness.baseColorFactor.empty()) {
        result.baseColorFactor = {
            static_cast<float>(material.pbrMetallicRoughness.baseColorFactor[0]),
            static_cast<float>(material.pbrMetallicRoughness.baseColorFactor[1]),
            static_cast<float>(material.pbrMetallicRoughness.baseColorFactor[2]),
            static_cast<float>(material.pbrMetallicRoughness.baseColorFactor[3])
        };
    }
    
    result.metallicFactor = material.pbrMetallicRoughness.metallicFactor;
    result.roughnessFactor = material.pbrMetallicRoughness.roughnessFactor;
    
    if (!material.emissiveFactor.empty()) {
        result.emissiveFactor = {
            static_cast<float>(material.emissiveFactor[0]),
            static_cast<float>(material.emissiveFactor[1]),
            static_cast<float>(material.emissiveFactor[2])
        };
    }
    
    return result;
}

NS::SharedPtr<MTL::Texture> GLTFLoader::loadTexture(
    const tinygltf::Model& model,
    const tinygltf::Texture& texture) {
    
    const tinygltf::Image& image = model.images[texture.source];
    
    MTL::TextureDescriptor* textureDesc = MTL::TextureDescriptor::alloc()->init();
    textureDesc->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
    textureDesc->setWidth(image.width);
    textureDesc->setHeight(image.height);
    textureDesc->setStorageMode(MTL::StorageModeShared);
    textureDesc->setUsage(MTL::TextureUsageShaderRead);
    
    NS::SharedPtr<MTL::Texture> metalTexture = NS::TransferPtr(_device->newTexture(textureDesc));

    textureDesc->release();
    
    MTL::Region region(0, 0, image.width, image.height);
    metalTexture->replaceRegion(region, 0, image.image.data(), 
                               image.width * 4);
    
    return metalTexture;
}