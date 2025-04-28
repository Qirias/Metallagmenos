#pragma once

#include "../pch.hpp"
#include <Metal/Metal.hpp>
#include "resourceManager.hpp"
#include "resourceNames.hpp"
#include "../components/mesh.hpp"

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
    
    // Ray tracing resources
    std::vector<MTL::AccelerationStructure*> primitiveAccelerationStructures;
    MTL::Buffer* resourceBuffer = nullptr;
    size_t totalTriangles = 0;
};