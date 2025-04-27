#pragma once

#include <Metal/Metal.hpp>
#include "../pch.hpp"
#include "../components/mesh.hpp"
#include "resourceManager.hpp"

class RayTracingManager {
public:
    RayTracingManager(MTL::Device* device, ResourceManager* resourceManager);
    ~RayTracingManager();
    
    void setupAccelerationStructures(const std::vector<Mesh*>& meshes);
    void setupTriangleResources(const std::vector<Mesh*>& meshes);
    
    MTL::AccelerationStructure* getPrimitiveAccelerationStructure() const;
    MTL::Buffer* getResourceBuffer() const;
    size_t getTotalTriangles() const { return totalTriangles; }
    
private:
    MTL::Device* device;
    ResourceManager* resourceManager;
    
    std::vector<MTL::AccelerationStructure*> primitiveAccelerationStructures;
    MTL::Buffer* resourceBuffer = nullptr;
    size_t totalTriangles = 0;
};