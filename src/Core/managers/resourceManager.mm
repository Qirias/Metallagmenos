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
    
    if (buffer && label) {
        buffer->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
        registerResource(buffer, label);
    }
    
    if (buffer && resourceTracker.find(buffer) == resourceTracker.end()) {
        managedResources.push_back(buffer);
        resourceTracker.insert(buffer);
    }
    
    return buffer;
}

MTL::Buffer* ResourceManager::createBuffer(size_t size, const void* initialData,
                                          MTL::ResourceOptions options,
                                          BufferName name) {
    std::string label = ResourceNames::toString(name);
    return createBuffer(size, initialData, options, label.c_str());
}

MTL::Texture* ResourceManager::createTexture(const MTL::TextureDescriptor* descriptor, 
                                           const char* label) {
    MTL::Texture* texture = device->newTexture(descriptor);
    
    if (texture && label) {
        texture->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
        registerResource(texture, label);
    }
    
    if (texture && resourceTracker.find(texture) == resourceTracker.end()) {
        managedResources.push_back(texture);
        resourceTracker.insert(texture);
    }
    
    return texture;
}

MTL::Texture* ResourceManager::createTexture(const MTL::TextureDescriptor* descriptor,
                                           TextureName name) {
    std::string label = ResourceNames::toString(name);
    return createTexture(descriptor, label.c_str());
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

MTL::Texture* ResourceManager::createRenderTargetTexture(uint32_t width, uint32_t height,
                                                       MTL::PixelFormat format,
                                                       TextureName name) {
    std::string label = ResourceNames::toString(name);
    return createRenderTargetTexture(width, height, format, label.c_str());
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

MTL::Texture* ResourceManager::createDepthStencilTexture(uint32_t width, uint32_t height,
                                                       TextureName name) {
    std::string label = ResourceNames::toString(name);
    return createDepthStencilTexture(width, height, label.c_str());
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

MTL::Texture* ResourceManager::createGBufferTexture(uint32_t width, uint32_t height,
                                                  MTL::PixelFormat format,
                                                  TextureName name) {
    std::string label = ResourceNames::toString(name);
    return createGBufferTexture(width, height, format, label.c_str());
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

MTL::Texture* ResourceManager::createRaytracingOutputTexture(uint32_t width, uint32_t height,
                                                          TextureName name) {
    std::string label = ResourceNames::toString(name);
    return createRaytracingOutputTexture(width, height, label.c_str());
}

MTL::AccelerationStructure* ResourceManager::createAccelerationStructure(
    MTL::AccelerationStructureDescriptor* descriptor,
    const char* label) {
    
    MTL::AccelerationStructureSizes sizes = device->accelerationStructureSizes(descriptor);
    MTL::AccelerationStructure* accelStructure = device->newAccelerationStructure(sizes.accelerationStructureSize);
    
    if (accelStructure && label) {
        accelStructure->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
        registerResource(accelStructure, label);
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
    
    if (accelStructure && label) {
        accelStructure->setLabel(NS::String::string(label, NS::ASCIIStringEncoding));
        registerResource(accelStructure, label);
    }
    
    if (accelStructure && resourceTracker.find(accelStructure) == resourceTracker.end()) {
        managedResources.push_back(accelStructure);
        resourceTracker.insert(accelStructure);
    }
    
    return accelStructure;
}

void ResourceManager::registerResource(MTL::Resource* resource, const std::string& name) {
    if (!resource || name.empty()) return;
    
    // Check if a resource with this name already exists
    auto it = resourceRegistry.find(name);
    if (it != resourceRegistry.end()) {
        // Warn if overwriting, but still update the registry
        std::cerr << "Warning: Overwriting resource with name '" << name << "'" << std::endl;
        resourceRegistry[name] = resource;
    } else {
        resourceRegistry[name] = resource;
    }
}

void ResourceManager::registerResource(MTL::Resource* resource, TextureName name) {
    registerResource(resource, ResourceNames::toString(name));
}

void ResourceManager::registerResource(MTL::Resource* resource, BufferName name) {
    registerResource(resource, ResourceNames::toString(name));
}

void ResourceManager::unregisterResource(const std::string& name) {
    resourceRegistry.erase(name);
}

void ResourceManager::unregisterResource(TextureName name) {
    unregisterResource(ResourceNames::toString(name));
}

void ResourceManager::unregisterResource(BufferName name) {
    unregisterResource(ResourceNames::toString(name));
}

MTL::Texture* ResourceManager::getTextureByName(const std::string& name) const {
    MTL::Resource* resource = getResourceByName(name);
    if (resource) {
        // Verify if the resource is a texture
        MTL::Texture* texture = static_cast<MTL::Texture*>(resource);
        if (texture) {
            return texture;
        }
    }
    return nullptr;
}

MTL::Buffer* ResourceManager::getBufferByName(const std::string& name) const {
    MTL::Resource* resource = getResourceByName(name);
    if (resource) {
        // Verify if the resource is a buffer
        MTL::Buffer* buffer = static_cast<MTL::Buffer*>(resource);
        if (buffer) {
            return buffer;
        }
    }
    return nullptr;
}

MTL::Resource* ResourceManager::getResourceByName(const std::string& name) const {
    auto it = resourceRegistry.find(name);
    if (it != resourceRegistry.end()) {
        return it->second;
    }
    return nullptr;
}

MTL::Texture* ResourceManager::getTexture(TextureName name) const {
    return getTextureByName(ResourceNames::toString(name));
}

MTL::Buffer* ResourceManager::getBuffer(BufferName name) const {
    return getBufferByName(ResourceNames::toString(name));
}

void ResourceManager::releaseResource(MTL::Resource* resource) {
    if (!resource) return;
    
    // Remove from managed resources list
    auto it = std::find(managedResources.begin(), managedResources.end(), resource);
    if (it != managedResources.end()) {
        managedResources.erase(it);
        resourceTracker.erase(resource);
        
        // Remove from registry if present
        for (auto regIt = resourceRegistry.begin(); regIt != resourceRegistry.end(); ) {
            if (regIt->second == resource) {
                regIt = resourceRegistry.erase(regIt);
            } else {
                ++regIt;
            }
        }
        
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
    resourceRegistry.clear();
}