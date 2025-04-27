#pragma once

#include <Metal/Metal.hpp>
#include "../pch.hpp"
#include "../vertexData.hpp"

class ResourceManager {
public:
    ResourceManager(MTL::Device* device);
    ~ResourceManager();

    // Buffer creation methods
    MTL::Buffer* createBuffer(size_t size, const void* initialData = nullptr, 
                            MTL::ResourceOptions options = MTL::ResourceStorageModeShared,
                            const char* label = nullptr);
    
    // Texture creation methods
    MTL::Texture* createTexture(const MTL::TextureDescriptor* descriptor, 
                              const char* label = nullptr);
    
    MTL::Texture* createRenderTargetTexture(uint32_t width, uint32_t height,
                                          MTL::PixelFormat format,
                                          const char* label = nullptr);
    
    MTL::Texture* createDepthStencilTexture(uint32_t width, uint32_t height,
                                          const char* label = nullptr);
    
    MTL::Texture* createGBufferTexture(uint32_t width, uint32_t height,
                                      MTL::PixelFormat format,
                                      const char* label = nullptr);
    
    MTL::Texture* createRaytracingOutputTexture(uint32_t width, uint32_t height,
                                              const char* label = nullptr);
    
   
    // Acceleration structure methods
    MTL::AccelerationStructure* createAccelerationStructure(MTL::AccelerationStructureDescriptor* descriptor, const char* label = nullptr);
        
    MTL::AccelerationStructure* createAccelerationStructure(size_t size, const char* label = nullptr);
    
    // Resource batch operations
    void releaseResource(MTL::Resource* resource);
    void releaseAllResources();
    
    // Utility methods
    void releaseTexture(MTL::Texture*& texture);
    
private:
    MTL::Device* device;
    std::vector<MTL::Resource*> managedResources;
    
    // Keep track of resources already in the managed list
    std::unordered_set<MTL::Resource*> resourceTracker;
};