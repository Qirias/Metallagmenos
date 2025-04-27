#pragma once

#include "../pch.hpp"
#include <Metal/Metal.hpp>
#include "../vertexData.hpp"
#include "resourceNames.hpp"

class ResourceManager {
public:
    ResourceManager(MTL::Device* device);
    ~ResourceManager();

    MTL::Buffer* createBuffer(size_t size, const void* initialData = nullptr, 
                            MTL::ResourceOptions options = MTL::ResourceStorageModeShared,
                            const char* label = nullptr);
    
    MTL::Buffer* createBuffer(size_t size, const void* initialData,
                            MTL::ResourceOptions options,
                            BufferName name);
    
    // Texture creation methods
    MTL::Texture* createTexture(const MTL::TextureDescriptor* descriptor, 
                              const char* label = nullptr);
    
    MTL::Texture* createTexture(const MTL::TextureDescriptor* descriptor,
                                TextureName name);
    
    MTL::Texture* createRenderTargetTexture(uint32_t width, uint32_t height,
                                            MTL::PixelFormat format,
                                            const char* label = nullptr);
    
    MTL::Texture* createRenderTargetTexture(uint32_t width, uint32_t height,
                                            MTL::PixelFormat format,
                                            TextureName name);
    
    MTL::Texture* createDepthStencilTexture(uint32_t width, uint32_t height,
                                            const char* label = nullptr);
    
    MTL::Texture* createDepthStencilTexture(uint32_t width, uint32_t height,
                                            TextureName name);
    
    MTL::Texture* createGBufferTexture(uint32_t width, uint32_t height,
                                       MTL::PixelFormat format,
                                       const char* label = nullptr);
    
    MTL::Texture* createGBufferTexture(uint32_t width, uint32_t height,
                                       MTL::PixelFormat format,
                                       TextureName name);
    
    MTL::Texture* createRaytracingOutputTexture(uint32_t width, uint32_t height,
                                                const char* label = nullptr);
    
    MTL::Texture* createRaytracingOutputTexture(uint32_t width, uint32_t height,
                                                TextureName name);
    
    MTL::AccelerationStructure* createAccelerationStructure(MTL::AccelerationStructureDescriptor* descriptor, const char* label = nullptr);
    MTL::AccelerationStructure* createAccelerationStructure(size_t size, const char* label = nullptr);
    
    MTL::Texture* getTextureByName(const std::string& name) const;
    MTL::Buffer* getBufferByName(const std::string& name) const;
    MTL::Resource* getResourceByName(const std::string& name) const;
    
    // Enum-based lookup
    MTL::Texture* getTexture(TextureName name) const;
    MTL::Buffer* getBuffer(BufferName name) const;
    
    void registerResource(MTL::Resource* resource, const std::string& name);
    void registerResource(MTL::Resource* resource, TextureName name);
    void registerResource(MTL::Resource* resource, BufferName name);
    void unregisterResource(const std::string& name);
    void unregisterResource(TextureName name);
    void unregisterResource(BufferName name);
    
    // Resource batch operations
    void releaseResource(MTL::Resource* resource);
    void releaseAllResources();
    
    void releaseTexture(MTL::Texture*& texture);
private:
    MTL::Device* device;
    std::vector<MTL::Resource*> managedResources;
    
    // Keep track of resources already in the managed list
    std::unordered_set<MTL::Resource*> resourceTracker;
    
    // Resource registry by name
    std::unordered_map<std::string, MTL::Resource*> resourceRegistry;
};