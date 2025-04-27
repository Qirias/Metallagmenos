#include "resourceManager.hpp"

ResourceManager::ResourceManager(MTL::Device* device) : device(device) {
}

ResourceManager::~ResourceManager() {
    releaseAllResources();
}

MTL::Buffer* ResourceManager::createBuffer(size_t size, const void* initialData, 
                                          MTL::ResourceOptions options,
                                          const char* label) {
    MTL::Buffer* buffer = nullptr;
    
    if (initialData) {
        buffer = device->newBuffer(initialData, size, options);
    } else {
        buffer = device->newBuffer(size, options);
    }
    
    if (label && buffer) {
        buffer->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
    }
    
    if (buffer && resourceTracker.find(buffer) == resourceTracker.end()) {
        managedResources.push_back(buffer);
        resourceTracker.insert(buffer);
    }
    
    return buffer;
}

MTL::Texture* ResourceManager::createTexture(const MTL::TextureDescriptor* descriptor, 
                                           const char* label) {
    MTL::Texture* texture = device->newTexture(descriptor);
    
    if (label && texture) {
        texture->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
    }
    
    if (texture && resourceTracker.find(texture) == resourceTracker.end()) {
        managedResources.push_back(texture);
        resourceTracker.insert(texture);
    }
    
    return texture;
}

MTL::Texture* ResourceManager::createRenderTargetTexture(uint32_t width, uint32_t height,
                                                       MTL::PixelFormat format,
                                                       const char* label) {
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setPixelFormat(format);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setStorageMode(MTL::StorageModeShared);
    desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
    
    MTL::Texture* texture = createTexture(desc, label);
    desc->release();
    
    return texture;
}

MTL::Texture* ResourceManager::createDepthStencilTexture(uint32_t width, uint32_t height,
                                                       const char* label) {
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setStorageMode(MTL::StorageModePrivate);
    desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
    
    MTL::Texture* texture = createTexture(desc, label);
    desc->release();
    
    return texture;
}

MTL::Texture* ResourceManager::createGBufferTexture(uint32_t width, uint32_t height,
                                                  MTL::PixelFormat format,
                                                  const char* label) {
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setPixelFormat(format);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setMipmapLevelCount(1);
    desc->setTextureType(MTL::TextureType2D);
    desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
    desc->setStorageMode(MTL::StorageModeShared);
    
    MTL::Texture* texture = createTexture(desc, label);
    desc->release();
    
    return texture;
}

MTL::Texture* ResourceManager::createRaytracingOutputTexture(uint32_t width, uint32_t height,
                                                          const char* label) {
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setTextureType(MTL::TextureType2D);
    desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setStorageMode(MTL::StorageModeShared);
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    MTL::Texture* texture = createTexture(desc, label);
    desc->release();
    
    return texture;
}

MTL::AccelerationStructure* ResourceManager::createAccelerationStructure(
    MTL::AccelerationStructureDescriptor* descriptor,
    const char* label) {
    
    MTL::AccelerationStructureSizes sizes = device->accelerationStructureSizes(descriptor);
    MTL::AccelerationStructure* accelStructure = device->newAccelerationStructure(sizes.accelerationStructureSize);
    
    if (label && accelStructure) {
        accelStructure->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
    }
    
    if (accelStructure && resourceTracker.find(accelStructure) == resourceTracker.end()) {
        managedResources.push_back(accelStructure);
        resourceTracker.insert(accelStructure);
    }
    
    return accelStructure;
}

MTL::AccelerationStructure* ResourceManager::createAccelerationStructure(
    size_t size,
    const char* label) {
    
    MTL::AccelerationStructure* accelStructure = device->newAccelerationStructure(size);
    
    if (label && accelStructure) {
        accelStructure->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
    }
    
    if (accelStructure && resourceTracker.find(accelStructure) == resourceTracker.end()) {
        managedResources.push_back(accelStructure);
        resourceTracker.insert(accelStructure);
    }
    
    return accelStructure;
}

void ResourceManager::releaseResource(MTL::Resource* resource) {
    if (!resource) return;
    
    auto it = std::find(managedResources.begin(), managedResources.end(), resource);
    if (it != managedResources.end()) {
        resourceTracker.erase(resource);
        managedResources.erase(it);
        resource->release();
    }
}

void ResourceManager::releaseTexture(MTL::Texture*& texture) {
    if (texture) {
        releaseResource(texture);
        texture = nullptr;
    }
}

void ResourceManager::releaseAllResources() {
    for (auto resource : managedResources) {
        if (resource) {
            resource->release();
        }
    }
    managedResources.clear();
    resourceTracker.clear();
}