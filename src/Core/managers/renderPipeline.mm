#include "renderPipeline.hpp"

MTL::RenderPipelineState* RenderPipeline::createRenderPipeline(const RenderPipelineConfig& config) {
    assert(device && library && "RenderPipeline not initialized!");
    NS::Error* error = nullptr;

    MTL::RenderPipelineDescriptor* descriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    descriptor->setLabel(NS::String::string(config.label.c_str(), NS::ASCIIStringEncoding));

    MTL::Function* vertexFunction = library->newFunction(NS::String::string(config.vertexFunctionName.c_str(), NS::ASCIIStringEncoding));
    MTL::Function* fragmentFunction = library->newFunction(NS::String::string(config.fragmentFunctionName.c_str(), NS::ASCIIStringEncoding));

    assert(vertexFunction && "Failed to load vertex shader!");
    
    if (config.fragmentFunctionName != "")
        assert(fragmentFunction && "Failed to load fragment shader!"); 
    
    descriptor->setVertexFunction(vertexFunction);
    descriptor->setFragmentFunction(fragmentFunction);
    
    if (config.vertexDescriptor) {
        descriptor->setVertexDescriptor(config.vertexDescriptor);
    }

    descriptor->colorAttachments()->object(0)->setPixelFormat(config.colorPixelFormat);
    descriptor->setDepthAttachmentPixelFormat(config.depthPixelFormat);
    descriptor->setStencilAttachmentPixelFormat(config.stencilPixelFormat);

    for (const auto& [index, format] : config.colorAttachments) {
        descriptor->colorAttachments()->object(index)->setPixelFormat(format);
    }

    MTL::RenderPipelineState* pipelineState = device->newRenderPipelineState(descriptor, &error);

    vertexFunction->release();
    fragmentFunction->release();
    descriptor->release();

    assertValid(pipelineState, error, config.label);

    return pipelineState;
}

MTL::ComputePipelineState* RenderPipeline::createComputePipeline(const ComputePipelineConfig& config) {
    assert(device && library && "RenderPipeline not initialized!");
    NS::Error* error = nullptr;

    MTL::Function* computeFunction = library->newFunction(NS::String::string(config.computeFunctionName.c_str(), NS::ASCIIStringEncoding));
    assert(computeFunction && "Failed to load compute function!");

    MTL::ComputePipelineState* pipelineState = device->newComputePipelineState(computeFunction, &error);
    
    computeFunction->release();
    
    assertValid(pipelineState, error, config.label);
    return pipelineState;
}

MTL::DepthStencilState* RenderPipeline::createDepthStencilState(const DepthStencilConfig& config) {
    assert(device && "RenderPipeline not initialized!");
    
    MTL::DepthStencilDescriptor* descriptor = MTL::DepthStencilDescriptor::alloc()->init();
    descriptor->setLabel(NS::String::string(config.label.c_str(), NS::ASCIIStringEncoding));
    descriptor->setDepthCompareFunction(config.depthCompareFunction);
    descriptor->setDepthWriteEnabled(config.depthWriteEnabled);
    
    if (config.frontStencil) {
        MTL::StencilDescriptor* frontStencil = MTL::StencilDescriptor::alloc()->init();
        frontStencil->setStencilCompareFunction(config.frontStencil->stencilCompareFunction);
        frontStencil->setStencilFailureOperation(config.frontStencil->stencilFailureOperation);
        frontStencil->setDepthFailureOperation(config.frontStencil->depthFailureOperation);
        frontStencil->setDepthStencilPassOperation(config.frontStencil->depthStencilPassOperation);
        frontStencil->setReadMask(config.frontStencil->readMask);
        frontStencil->setWriteMask(config.frontStencil->writeMask);
        descriptor->setFrontFaceStencil(frontStencil);
        frontStencil->release();
    }
    
    if (config.backStencil) {
        MTL::StencilDescriptor* backStencil = MTL::StencilDescriptor::alloc()->init();
        backStencil->setStencilCompareFunction(config.backStencil->stencilCompareFunction);
        backStencil->setStencilFailureOperation(config.backStencil->stencilFailureOperation);
        backStencil->setDepthFailureOperation(config.backStencil->depthFailureOperation);
        backStencil->setDepthStencilPassOperation(config.backStencil->depthStencilPassOperation);
        backStencil->setReadMask(config.backStencil->readMask);
        backStencil->setWriteMask(config.backStencil->writeMask);
        descriptor->setBackFaceStencil(backStencil);
        backStencil->release();
    }
    
    MTL::DepthStencilState* depthStencilState = device->newDepthStencilState(descriptor);
    descriptor->release();
    
    return depthStencilState;
}

void RenderPipeline::assertValid(MTL::RenderPipelineState* pipelineState, NS::Error* error, const std::string& label) {
    if (!pipelineState) {
        fprintf(stderr, "Failed to create render pipeline '%s': %s\n",
                label.c_str(), error->localizedDescription()->utf8String());
        assert(false && "Render pipeline creation failed!");
    }
}

void RenderPipeline::assertValid(MTL::ComputePipelineState* pipelineState, NS::Error* error, const std::string& label) {
    if (!pipelineState) {
        fprintf(stderr, "Failed to create compute pipeline '%s': %s\n",
                label.c_str(), error->localizedDescription()->utf8String());
        assert(false && "Compute pipeline creation failed!");
    }
}
