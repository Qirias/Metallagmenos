#pragma once

#include <Metal/Metal.hpp>
#include <string>
#include <unordered_map>
#include <cassert>

struct RenderPipelineConfig {
    std::string label;
    std::string vertexFunctionName;
    std::string fragmentFunctionName;
    MTL::PixelFormat colorPixelFormat = MTL::PixelFormatBGRA8Unorm;
    MTL::PixelFormat depthPixelFormat = MTL::PixelFormatDepth32Float_Stencil8;
    MTL::PixelFormat stencilPixelFormat = MTL::PixelFormatDepth32Float_Stencil8;
    MTL::VertexDescriptor* vertexDescriptor = nullptr;

    std::unordered_map<int, MTL::PixelFormat> colorAttachments;
};

struct ComputePipelineConfig {
    std::string label;
    std::string computeFunctionName;
};

struct StencilConfig {
    MTL::CompareFunction stencilCompareFunction = MTL::CompareFunctionAlways;
    MTL::StencilOperation stencilFailureOperation = MTL::StencilOperationKeep;
    MTL::StencilOperation depthFailureOperation = MTL::StencilOperationKeep;
    MTL::StencilOperation depthStencilPassOperation = MTL::StencilOperationKeep;
    uint32_t readMask = 0xFF;
    uint32_t writeMask = 0xFF;
};

struct DepthStencilConfig {
    std::string label;
    MTL::CompareFunction depthCompareFunction = MTL::CompareFunctionLess;
    bool depthWriteEnabled = true;
    std::optional<StencilConfig> frontStencil;
    std::optional<StencilConfig> backStencil;
};

class RenderPipeline {
public:
    RenderPipeline() = default;
    ~RenderPipeline() = default;
    
    void initialize(MTL::Device* device, MTL::Library* library) {
        this->device = device;
        this->library = library;
    }
    MTL::RenderPipelineState* createRenderPipeline(const RenderPipelineConfig& config);
    MTL::ComputePipelineState* createComputePipeline(const ComputePipelineConfig& config);
    MTL::DepthStencilState* createDepthStencilState(const DepthStencilConfig& config);
    
private:
    MTL::Device*    device;
    MTL::Library*   library;
    
    void assertValid(MTL::RenderPipelineState* pipelineState, NS::Error* error, const std::string& label);
    void assertValid(MTL::ComputePipelineState* pipelineState, NS::Error* error, const std::string& label);
};
