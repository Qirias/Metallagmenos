#include "rayTracingManager.hpp"

RayTracingManager::RayTracingManager(MTL::Device* device, ResourceManager* resourceManager)
    : device(device), resourceManager(resourceManager), totalTriangles(0) {
}

RayTracingManager::~RayTracingManager() {
    // Resources are managed by the ResourceManager, so we don't need to explicitly release them
}

void RayTracingManager::setupAccelerationStructures(const std::vector<Mesh*>& meshes) {
    // Create a separate command queue for acceleration structure building
    MTL::CommandQueue* commandQueue = device->newCommandQueue();
    MTL::CommandBuffer* commandBuffer = commandQueue->commandBuffer();

    std::vector<Vertex> mergedVertices;
    std::vector<uint32_t> mergedIndices;

    size_t vertexOffset = 0;
    totalTriangles = 0;
    
    for (const auto& mesh : meshes) {
        matrix_float4x4 modelMatrix = mesh->getTransformMatrix();

        for (const auto& vertex : mesh->vertices) {
            Vertex transformedVertex = vertex;
            transformedVertex.position = modelMatrix * vertex.position;
            mergedVertices.push_back(transformedVertex);
        }

        for (size_t index : mesh->vertexIndices) {
            mergedIndices.push_back(static_cast<uint32_t>(index + vertexOffset));
        }

        vertexOffset += mesh->vertices.size();
        totalTriangles += mesh->triangleCount;
    }
    
    // Use ResourceManager to create vertex and index buffers
    size_t vertexBufferSize = mergedVertices.size() * sizeof(Vertex);
    MTL::Buffer* mergedVertexBuffer = resourceManager->createBuffer(
        vertexBufferSize, 
        mergedVertices.data(), 
        MTL::ResourceStorageModeShared, 
        "mergedVertexBuffer"
    );

    size_t indexBufferSize = mergedIndices.size() * sizeof(uint32_t);
    MTL::Buffer* mergedIndexBuffer = resourceManager->createBuffer(
        indexBufferSize, 
        mergedIndices.data(), 
        MTL::ResourceStorageModeShared, 
        "mergedIndexBuffer"
    );

    MTL::AccelerationStructureTriangleGeometryDescriptor* geometryDescriptor = 
        MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();

    geometryDescriptor->setVertexBuffer(mergedVertexBuffer);
    geometryDescriptor->setVertexStride(sizeof(Vertex));
    geometryDescriptor->setVertexFormat(MTL::AttributeFormatFloat3);

    geometryDescriptor->setIndexBuffer(mergedIndexBuffer);
    geometryDescriptor->setIndexType(MTL::IndexTypeUInt32);
    geometryDescriptor->setTriangleCount(static_cast<uint32_t>(totalTriangles));

    NS::Array* geometryDescriptors = NS::Array::array(geometryDescriptor);

    // Set the triangle geometry descriptors in the acceleration structure descriptor
    MTL::PrimitiveAccelerationStructureDescriptor* accelerationStructureDescriptor = 
        MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
    accelerationStructureDescriptor->setGeometryDescriptors(geometryDescriptors);

    // Get acceleration structure sizes
    MTL::AccelerationStructureSizes sizes = device->accelerationStructureSizes(accelerationStructureDescriptor);

    // Create the acceleration structure through ResourceManager
    MTL::AccelerationStructure* accelerationStructure = resourceManager->createAccelerationStructure(
        sizes.accelerationStructureSize, 
        "Primary Acceleration Structure"
    );

    // Create a scratch buffer for building the acceleration structure
    MTL::Buffer* scratchBuffer = resourceManager->createBuffer(
        sizes.buildScratchBufferSize, 
        nullptr, 
        MTL::ResourceStorageModePrivate, 
        "scratchBuffer"
    );

    // Build the acceleration structure
    MTL::AccelerationStructureCommandEncoder* commandEncoder = commandBuffer->accelerationStructureCommandEncoder();
    commandEncoder->buildAccelerationStructure(accelerationStructure, accelerationStructureDescriptor, scratchBuffer, 0);
    commandEncoder->endEncoding();

    // Commit and wait for the command buffer to complete
    commandBuffer->commit();
    commandBuffer->waitUntilCompleted();

    // Store the acceleration structure for later use
    primitiveAccelerationStructures.push_back(accelerationStructure);

    geometryDescriptor->release();
    geometryDescriptors->release();
    accelerationStructureDescriptor->release();
    
    // Let ResourceManager handle the release
    resourceManager->releaseResource(scratchBuffer);
    
    commandBuffer->release();
    commandQueue->release();
}

void RayTracingManager::setupTriangleResources(const std::vector<Mesh*>& meshes) {
    struct TriangleData {
        simd::float4 normals[3];
        simd::float4 colors[3];
    };
    
    size_t resourceStride = sizeof(TriangleData);
    size_t bufferLength = resourceStride * totalTriangles;

    resourceBuffer = resourceManager->createBuffer(
        bufferLength, 
        nullptr, 
        MTL::ResourceStorageModeShared, 
        BufferName::TriangleResources
    );

    TriangleData* resourceBufferContents = (TriangleData*)((uint8_t*)(resourceBuffer->contents()));
    size_t triangleIndex = 0;

    for (int m = 0; m < meshes.size(); m++) {
        simd::float4 meshColor;
        
        if (meshes[m]->meshInfo.isEmissive) {
            meshColor = simd::float4{
                meshes[m]->meshInfo.emissiveColor.x,
                meshes[m]->meshInfo.emissiveColor.y,
                meshes[m]->meshInfo.emissiveColor.z,
                -1.0f  // Emissive
            };
        } else {
            meshColor = simd::float4{
                meshes[m]->meshInfo.color.x,
                meshes[m]->meshInfo.color.y,
                meshes[m]->meshInfo.color.z,
                1.0f  // Non-emissive
            };
        }
        
        for (size_t i = 0; i < meshes[m]->vertexIndices.size(); i += 3) {
            TriangleData& triangle = resourceBufferContents[triangleIndex++];

            for (size_t j = 0; j < 3; ++j) {
                size_t vertexIndex = meshes[m]->vertexIndices[i + j];
                triangle.normals[j] = meshes[m]->vertices[vertexIndex].normal;
                triangle.colors[j] = meshColor;
            }
        }
    }
}

MTL::AccelerationStructure* RayTracingManager::getPrimitiveAccelerationStructure() const {
    if (primitiveAccelerationStructures.empty()) {
        return nullptr;
    }
    return primitiveAccelerationStructures[0];
}

MTL::Buffer* RayTracingManager::getResourceBuffer() const {
    return resourceBuffer;
}