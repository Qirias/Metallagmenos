//
//  mesh.cpp
//  Metal-Tutorial
//

#include "mesh.hpp"
#include "../../data/shaders/shaderTypes.hpp"

#include <iostream>
#include <unordered_map>
#include <string>

// For tinyobjloader
Mesh::Mesh(std::string filePath, MTL::Device* metalDevice, MTL::VertexDescriptor* vertexDescriptor) {
    device = metalDevice;
    loadObj(filePath);
    createBuffers(vertexDescriptor);
}

// For tinyGLTF
Mesh::Mesh(MTL::Device* device, const Vertex* vertexData, size_t vertexCount,
		   const uint32_t* indexData, size_t indexCount)
	: device(device) {
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
	normalTextures->release();
	normalTextureInfos->release();
    diffuseTextures->release();
    diffuseTextureInfos->release();
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
				std::cout << "Diffuse Texture " << textureIndex << ": " << texturePath << std::endl;
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
				std::cout << "Normal Texture " << textureIndex << ": " << texturePath << std::endl;
			}
		}
	}

	// Create texture arrays
	diffuseTexturesArray = new TextureArray(diffuseFilePaths, device, TextureType::DIFFUSE);
	normalTexturesArray = new TextureArray(normalFilePaths, device, TextureType::NORMAL);

	// Process geometry
	vertices.clear();
	vertexIndices.clear();
	vertexMap.clear();

	for (const auto& shape : shapes) {
		size_t index_offset = 0;
		
		for (size_t f = 0; f < shape.mesh.num_face_vertices.size(); f++) {
			int material_id = shape.mesh.material_ids[f];
			if (material_id < 0 || material_id >= materials.size()) {
				std::cerr << "Invalid material ID: " << material_id << std::endl;
				continue;
			}
			
			// Get texture indices for both diffuse and normal maps
			int diffuseTextureIndex = -1;
			int normalTextureIndex = -1;
			
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
						0.0f
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
				
				if (idx.texcoord_index >= 0) {
					vertex.textureCoordinate = {
						vertexArrays.texcoords[2 * idx.texcoord_index + 0],
						vertexArrays.texcoords[2 * idx.texcoord_index + 1]
					};
				}
				
				vertex.diffuseTextureIndex = diffuseTextureIndex;
				vertex.normalTextureIndex = normalTextureIndex;
				
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
            
            triangleCount++;
			index_offset += fv;
		}
	}
	
	calculateTangentSpace(vertices, vertexIndices);
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
    // Create Vertex Buffers
    unsigned long vertexCount = vertices.size();
    std::cout << "Mesh Vertex Count: " << vertexCount << std::endl;
    unsigned long vertexBufferSize = sizeof(Vertex) * vertices.size();
    std::cout << "Mesh Vertex Buffer Size: " << vertexBufferSize << std::endl;
    vertexBuffer = device->newBuffer(vertices.data(), vertexBufferSize, MTL::ResourceStorageModeShared);
    vertexBuffer->setLabel(NS::String::string("Mesh Vertex Buffer", NS::ASCIIStringEncoding));
    // Create Index Buffer
    indexCount = vertexIndices.size();
    unsigned long indexBufferSize = sizeof(uint32_t) * vertexIndices.size();
    indexBuffer = device->newBuffer(vertexIndices.data(), indexBufferSize, MTL::ResourceStorageModeShared);
	
    // Pass previously created Texture Array Pointer
	diffuseTextures = diffuseTexturesArray->diffuseTextureArray;
    diffuseTextures->setLabel(NS::String::string("Diffuse Texture Array", NS::ASCIIStringEncoding));
    // Create Diffuse Texture Info
    size_t diffuseBufferSize = diffuseTexturesArray->diffuseTextureInfos.size() * sizeof(TextureInfo);
    std::cout << "Diffuse Texture Count: " << diffuseTexturesArray->diffuseTextureInfos.size() << std::endl;
    std::cout << "TextureInfo size: " << sizeof(TextureInfo) << std::endl;
    diffuseTextureInfos = device->newBuffer(diffuseTexturesArray->diffuseTextureInfos.data(), diffuseBufferSize, MTL::ResourceStorageModeShared);
    diffuseTextureInfos->setLabel(NS::String::string("Diffuse Texture Info Array", NS::ASCIIStringEncoding));
	
	// Pass previously created Texture Array Pointer
	normalTextures = normalTexturesArray->normalTextureArray;
	normalTextures->setLabel(NS::String::string("Normal Texture Array", NS::ASCIIStringEncoding));
	// Create normal Texture Info
	size_t normalBufferSize = normalTexturesArray->normalTextureInfos.size() * sizeof(TextureInfo);
	std::cout << "Normal Texture Count: " << normalTexturesArray->normalTextureInfos.size() << std::endl;
	std::cout << "TextureInfo size: " << sizeof(TextureInfo) << std::endl;
	normalTextureInfos = device->newBuffer(normalTexturesArray->normalTextureInfos.data(), normalBufferSize, MTL::ResourceStorageModeShared);
	normalTextureInfos->setLabel(NS::String::string("Normal Texture Info Array", NS::ASCIIStringEncoding));
	
	if (vertexDescriptor) {
		// Position
		vertexDescriptor->attributes()->object(VertexAttributePosition)->setFormat(MTL::VertexFormatFloat4);
		vertexDescriptor->attributes()->object(VertexAttributePosition)->setOffset(offsetof(Vertex, position));
		vertexDescriptor->attributes()->object(VertexAttributePosition)->setBufferIndex(0);

		// Normal
		vertexDescriptor->attributes()->object(VertexAttributeNormal)->setFormat(MTL::VertexFormatFloat4);
		vertexDescriptor->attributes()->object(VertexAttributeNormal)->setOffset(offsetof(Vertex, normal));
		vertexDescriptor->attributes()->object(VertexAttributeNormal)->setBufferIndex(0);

		// Tangent
		vertexDescriptor->attributes()->object(VertexAttributeTangent)->setFormat(MTL::VertexFormatFloat4);
		vertexDescriptor->attributes()->object(VertexAttributeTangent)->setOffset(offsetof(Vertex, tangent));
		vertexDescriptor->attributes()->object(VertexAttributeTangent)->setBufferIndex(0);

		// Bitangent
		vertexDescriptor->attributes()->object(VertexAttributeBitangent)->setFormat(MTL::VertexFormatFloat4);
		vertexDescriptor->attributes()->object(VertexAttributeBitangent)->setOffset(offsetof(Vertex, bitangent));
		vertexDescriptor->attributes()->object(VertexAttributeBitangent)->setBufferIndex(0);

		// TextureCoordinate
		vertexDescriptor->attributes()->object(VertexAttributeTexcoord)->setFormat(MTL::VertexFormatFloat2);
		vertexDescriptor->attributes()->object(VertexAttributeTexcoord)->setOffset(offsetof(Vertex, textureCoordinate));
		vertexDescriptor->attributes()->object(VertexAttributeTexcoord)->setBufferIndex(0);
		
		// DiffuseTextureIndex
		vertexDescriptor->attributes()->object(VertexAttributeDiffuseIndex)->setFormat(MTL::VertexFormatInt);
		vertexDescriptor->attributes()->object(VertexAttributeDiffuseIndex)->setOffset(offsetof(Vertex, diffuseTextureIndex));
		vertexDescriptor->attributes()->object(VertexAttributeDiffuseIndex)->setBufferIndex(0);
		
		// NormalTextureIndex
		vertexDescriptor->attributes()->object(VertexAttributeNormalIndex)->setFormat(MTL::VertexFormatInt);
		vertexDescriptor->attributes()->object(VertexAttributeNormalIndex)->setOffset(offsetof(Vertex, normalTextureIndex));
		vertexDescriptor->attributes()->object(VertexAttributeNormalIndex)->setBufferIndex(0);

		// Set layout
		vertexDescriptor->layouts()->object(0)->setStride(sizeof(Vertex));
	}
}
