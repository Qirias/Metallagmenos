#include "gltfLoader.hpp"

GLTFLoader::GLTFLoader(MTL::Device* device) : _device(device) {}


GLTFLoader::GLTFModel GLTFLoader::loadModel(const std::string& filepath) {
	tinygltf::Model gltfModel;
	tinygltf::TinyGLTF loader;
	std::string err, warn;
	
	// Set up the callbacks before loading
	loader.SetImageLoader(&GLTFLoader::LoadImageData, nullptr);
	
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
	std::vector<Vertex> allVertices;
	std::vector<uint32_t> allIndices;
	
	// Process each mesh
	for (const auto& mesh : gltfModel.meshes) {
		for (const auto& primitive : mesh.primitives) {
			// Get the processed mesh data
			auto processedMesh = processMesh(gltfModel, mesh, primitive);
			
			// Calculate the base index for this primitive
			uint32_t indexOffset = static_cast<uint32_t>(allVertices.size());
			
			// Add vertices
			allVertices.insert(allVertices.end(),
							 processedMesh.vertices.begin(),
							 processedMesh.vertices.end());
			
			// Add indices with offset
			for (uint32_t index : processedMesh.indices) {
				allIndices.push_back(index + indexOffset);
			}
			
			// Store the mesh for future reference if needed
//			model.meshes.push_back(Mesh(_device,
//									  processedMesh.vertices.data(),
//									  processedMesh.vertices.size(),
//									  processedMesh.indices.data(),
//									  processedMesh.indices.size()));
			
		}
	}
	
	// Store the combined vertex and index data
	model.vertices = std::move(allVertices);
	model.indices = std::move(allIndices);
	
	// Process materials
	for (const auto& material : gltfModel.materials) {
		model.materials.push_back(processMaterial(gltfModel, material));
	}
	
	// Validate the data
	if (model.vertices.empty() || model.indices.empty()) {
		throw std::runtime_error("Failed to load model: No vertex or index data found");
	}
	
	return model;
}


GLTFLoader::ProcessedMeshData GLTFLoader::processMesh(const tinygltf::Model& model,
													 const tinygltf::Mesh& mesh,
													 const tinygltf::Primitive& primitive) {
	ProcessedMeshData result;
	
	// Get buffer data for positions
	const float* positions = nullptr;
	const float* normals = nullptr;
	const float* texCoords = nullptr;
	size_t vertexCount = 0;
	
	// Get positions
	if (primitive.attributes.find("POSITION") != primitive.attributes.end()) {
		const tinygltf::Accessor& accessor = model.accessors[primitive.attributes.at("POSITION")];
		const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
		const tinygltf::Buffer& buffer = model.buffers[bufferView.buffer];
		
		// Calculate the actual byte offset into the buffer
		size_t byteOffset = bufferView.byteOffset + accessor.byteOffset;
		positions = reinterpret_cast<const float*>(&buffer.data[byteOffset]);
		vertexCount = accessor.count;
	}
	
	// Get normals
	if (primitive.attributes.find("NORMAL") != primitive.attributes.end()) {
		const tinygltf::Accessor& accessor = model.accessors[primitive.attributes.at("NORMAL")];
		const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
		const tinygltf::Buffer& buffer = model.buffers[bufferView.buffer];
		
		size_t byteOffset = bufferView.byteOffset + accessor.byteOffset;
		normals = reinterpret_cast<const float*>(&buffer.data[byteOffset]);
	}
	
	// Get texture coordinates
	if (primitive.attributes.find("TEXCOORD_0") != primitive.attributes.end()) {
		const tinygltf::Accessor& accessor = model.accessors[primitive.attributes.at("TEXCOORD_0")];
		const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
		const tinygltf::Buffer& buffer = model.buffers[bufferView.buffer];
		
		size_t byteOffset = bufferView.byteOffset + accessor.byteOffset;
		texCoords = reinterpret_cast<const float*>(&buffer.data[byteOffset]);
	}
	
	// Process vertices taking into account stride
	for (size_t i = 0; i < vertexCount; i++) {
		Vertex vertex{};
		
		// Handle positions with stride
		if (positions) {
			const tinygltf::Accessor& accessor = model.accessors[primitive.attributes.at("POSITION")];
			const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
			size_t stride = bufferView.byteStride ? bufferView.byteStride / sizeof(float) : 3;
			vertex.position = {
				positions[i * stride + 0],
				positions[i * stride + 1],
				positions[i * stride + 2]
			};
		}
		
		// Handle normals with stride
		if (normals) {
			const tinygltf::Accessor& accessor = model.accessors[primitive.attributes.at("NORMAL")];
			const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
			size_t stride = bufferView.byteStride ? bufferView.byteStride / sizeof(float) : 3;
			vertex.normal = {
				normals[i * stride + 0],
				normals[i * stride + 1],
				normals[i * stride + 2]
			};
		}
		
		// Handle texture coordinates with stride
		if (texCoords) {
			const tinygltf::Accessor& accessor = model.accessors[primitive.attributes.at("TEXCOORD_0")];
			const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
			size_t stride = bufferView.byteStride ? bufferView.byteStride / sizeof(float) : 2;
			vertex.textureCoordinate = {
				texCoords[i * stride + 0],
				texCoords[i * stride + 1]
			};
		}
		
		vertex.diffuseTextureIndex = primitive.material;
		result.vertices.push_back(vertex);
	}
	
	// Process indices
	if (primitive.indices >= 0) {
		const tinygltf::Accessor& accessor = model.accessors[primitive.indices];
		const tinygltf::BufferView& bufferView = model.bufferViews[accessor.bufferView];
		const tinygltf::Buffer& buffer = model.buffers[bufferView.buffer];
		
		size_t byteOffset = bufferView.byteOffset + accessor.byteOffset;
		const uint8_t* data = &buffer.data[byteOffset];
		
		switch (accessor.componentType) {
			case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT: {
				const uint16_t* indices = reinterpret_cast<const uint16_t*>(data);
				for (size_t i = 0; i < accessor.count; i++) {
					result.indices.push_back(static_cast<uint32_t>(indices[i]));
				}
				break;
			}
			case TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT: {
				const uint32_t* indices = reinterpret_cast<const uint32_t*>(data);
				for (size_t i = 0; i < accessor.count; i++) {
					result.indices.push_back(indices[i]);
				}
				break;
			}
			default:
				throw std::runtime_error("Unsupported index component type");
		}
	}
	
	return result;
}



GLTFLoader::GLTFMaterial GLTFLoader::processMaterial(
    const tinygltf::Model& model,
    const tinygltf::Material& material) {
    
    GLTFMaterial result;
    
    // Process PBR Metallic Roughness
    if (material.pbrMetallicRoughness.baseColorTexture.index >= 0) {
        const auto& texture = model.textures[material.pbrMetallicRoughness.baseColorTexture.index];
        result.baseColorTexture = loadTexture(model, texture);
    }
    
    if (material.pbrMetallicRoughness.metallicRoughnessTexture.index >= 0) {
        const auto& texture = model.textures[material.pbrMetallicRoughness.metallicRoughnessTexture.index];
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

bool GLTFLoader::LoadImageData(tinygltf::Image* image, const int imageIndex,
						 std::string* error, std::string* warning,
						 int req_width, int req_height,
						 const unsigned char* bytes, int size, void* userData) {
		
		int width, height, channels;
		unsigned char* data = stbi_load_from_memory(bytes, size, &width, &height, &channels, STBI_rgb_alpha);
		
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
