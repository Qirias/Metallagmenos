#pragma once

#include <Metal/Metal.hpp>
#include <string>
#include <unordered_map>
#include <cassert>

enum class RenderPipelineType {
    GBufferTextured,
    GBufferNonTextured,
    DirectionalLight,
    ForwardDebug
};

enum class ComputePipelineType {
    Raytracing,
    InitMinMaxDepth,
    MinMaxDepth,
    DirectionEncoding
};

enum class DepthStencilType {
    GBuffer,
    DirectionalLight
};

struct RenderPipelineConfig {
    std::string label;
    std::string vertexFunctionName;
    std::string fragmentFunctionName;
    MTL::PixelFormat colorPixelFormat = MTL::PixelFormatBGRA8Unorm;
    MTL::PixelFormat depthPixelFormat = MTL::PixelFormatDepth32Float_Stencil8;
    MTL::PixelFormat stencilPixelFormat = MTL::PixelFormatDepth32Float_Stencil8;
    MTL::VertexDescriptor* vertexDescriptor = nullptr;
    MTL::FunctionConstantValues* functionConstants = nullptr;

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
    ~RenderPipeline();
    
    void initialize(MTL::Device* device, MTL::Library* library) {
        this->device = device;
        this->library = library;
    }

    MTL::RenderPipelineState* getRenderPipeline(RenderPipelineType type);
    MTL::ComputePipelineState* getComputePipeline(ComputePipelineType type);
    MTL::DepthStencilState* getDepthStencilState(DepthStencilType type);

    void createRenderPipeline(RenderPipelineType type, const RenderPipelineConfig& config);
    void createComputePipeline(ComputePipelineType type, const ComputePipelineConfig& config);
    void createDepthStencilState(DepthStencilType type, const DepthStencilConfig& config);
    
private:
    MTL::Device*    device;
    MTL::Library*   library;

    std::unordered_map<RenderPipelineType, MTL::RenderPipelineState*>   renderPipelineStates;
    std::unordered_map<ComputePipelineType, MTL::ComputePipelineState*> computePipelineStates;
    std::unordered_map<DepthStencilType, MTL::DepthStencilState*>       depthStencilStates;

    MTL::RenderPipelineState* createRenderPipelineState(const RenderPipelineConfig& config);
    MTL::ComputePipelineState* createComputePipelineState(const ComputePipelineConfig& config);
    MTL::DepthStencilState* createDepthStencilState(const DepthStencilConfig& config);
    
    void assertValid(MTL::RenderPipelineState* pipelineState, NS::Error* error, const std::string& label);
    void assertValid(MTL::ComputePipelineState* pipelineState, NS::Error* error, const std::string& label);

    void cleanup();
};
