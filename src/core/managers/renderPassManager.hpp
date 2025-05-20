#pragma once

#include "../pch.hpp"
#include <Metal/Metal.hpp>
#include "resourceManager.hpp"
#include "renderPipeline.hpp"
#include "rayTracingManager.hpp"
#include "../components/mesh.hpp"
#include "../debug/debug.hpp"
#include "../editor/editor.hpp"
#include "../../data/shaders/shaderTypes.hpp"

// You can try different max cascade levels
constexpr int MAX_CASCADE_LEVEL = 6;
// You can't put any value of probe spacing and base ray
constexpr int PROBE_SPACING = 4;
constexpr int BASE_RAY = 16;

class RenderPassManager {
public:
    RenderPassManager(MTL::Device* device, 
                      ResourceManager* resourceManager,
                      RenderPipeline* renderPipelines,
                      RayTracingManager* rayTracingManager,
                      Debug* debug,
                      Editor* editor);
    ~RenderPassManager();
    
    // Render pipeline passes
    void drawMeshes(MTL::RenderCommandEncoder* renderCommandEncoder, const std::vector<Mesh*>& meshes, MTL::Buffer* frameDataBuffer);
    void drawGBuffer(MTL::RenderCommandEncoder* renderCommandEncoder, const std::vector<Mesh*>& meshes, MTL::Buffer* frameDataBuffer);
    void drawFinalGathering(MTL::RenderCommandEncoder* renderCommandEncoder, MTL::Buffer* frameDataBuffer);
    void drawDepthPrepass(MTL::CommandBuffer* commandBuffer, const std::vector<Mesh*>& meshes, MTL::Buffer* frameDataBuffer);
    void drawDebug(MTL::RenderCommandEncoder* commandEncoder, MTL::CommandBuffer* commandBuffer, MTL::Buffer* frameDataBuffer);
                  
    // Compute pipeline passes
    void dispatchRaytracing(MTL::CommandBuffer* commandBuffer, MTL::Buffer* frameDataBuffer, const std::vector<MTL::Buffer*>& cascadeBuffers, MTL::Buffer* probeData, MTL::Buffer* rayData);
    void dispatchTwoPassBlur(MTL::CommandBuffer* commandBuffer, MTL::Buffer* frameDataBuffer);
    void dispatchMinMaxDepthMipmaps(MTL::CommandBuffer* commandBuffer);

private:
    MTL::Device* device;
    ResourceManager* resourceManager;
    RenderPipeline* renderPipelines;
    RayTracingManager* rayTracingManager;
    Debug* debug;
    Editor* editor;
};
