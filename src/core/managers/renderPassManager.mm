// src/Core/managers/renderPassManager.mm
#include "renderPassManager.hpp"

RenderPassManager::RenderPassManager(MTL::Device* device, 
                                   ResourceManager* resourceManager,
                                   RenderPipeline* renderPipelines,
                                   RayTracingManager* rayTracingManager,
                                   Debug* debug,
                                   Editor* editor)
    : device(device)
    , resourceManager(resourceManager)
    , renderPipelines(renderPipelines)
    , rayTracingManager(rayTracingManager)
    , debug(debug)
    , editor(editor) {
}

RenderPassManager::~RenderPassManager() {
    // No need to release anything since we don't own the resources
}

void RenderPassManager::drawMeshes(MTL::RenderCommandEncoder* renderCommandEncoder,  const std::vector<Mesh*>& meshes, MTL::Buffer*& frameDataBuffer) {
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    
    for (int i = 0; i < meshes.size(); i++) {
        if (meshes[i]->meshHasTextures()) {
            renderCommandEncoder->setRenderPipelineState(renderPipelines->getRenderPipeline(RenderPipelineType::GBufferTextured));
        } else {
            renderCommandEncoder->setRenderPipelineState(renderPipelines->getRenderPipeline(RenderPipelineType::GBufferNonTextured));
        }

        renderCommandEncoder->setVertexBuffer(meshes[i]->vertexBuffer, 0, BufferIndexVertexData);
        
        matrix_float4x4 modelMatrix = meshes[i]->getTransformMatrix();
        renderCommandEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), BufferIndexVertexBytes);
        
        // Set any textures read/sampled from the render pipeline
        renderCommandEncoder->setFragmentTexture(meshes[i]->diffuseTextures, TextureIndexBaseColor);
        renderCommandEncoder->setFragmentBytes(&meshes[i]->meshInfo.isEmissive, sizeof(bool), BufferIndexIsEmissive);
        if (meshes[i]->meshInfo.isEmissive)
            renderCommandEncoder->setFragmentBytes(&meshes[i]->meshInfo.emissiveColor, sizeof(simd::float3), BufferIndexColor);
        else
            renderCommandEncoder->setFragmentBytes(&meshes[i]->meshInfo.color, sizeof(simd::float3), BufferIndexColor);
        renderCommandEncoder->setFragmentTexture(meshes[i]->normalTextures, TextureIndexNormal);
        renderCommandEncoder->setFragmentBuffer(meshes[i]->diffuseTextureInfos, 0, BufferIndexDiffuseInfo);
        renderCommandEncoder->setFragmentBuffer(meshes[i]->normalTextureInfos, 0, BufferIndexNormalInfo);
        
        MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
        renderCommandEncoder->drawIndexedPrimitives(typeTriangle, meshes[i]->indexCount, MTL::IndexTypeUInt32, meshes[i]->indexBuffer, 0);
    }
}

void RenderPassManager::drawGBuffer(MTL::RenderCommandEncoder* renderCommandEncoder, const std::vector<Mesh*>& meshes, MTL::Buffer*& frameDataBuffer) {
    if (!resourceManager->getTexture(TextureName::AlbedoGBuffer) ||
        !resourceManager->getTexture(TextureName::NormalGBuffer) || 
        !resourceManager->getTexture(TextureName::DepthGBuffer) || 
        !resourceManager->getTexture(TextureName::DepthStencilTexture)) {
        std::cerr << "Error: Missing textures for G-Buffer rendering" << std::endl;
        return;
    }

    renderCommandEncoder->pushDebugGroup(NS::String::string("Draw G-Buffer", NS::ASCIIStringEncoding));
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    renderCommandEncoder->setDepthStencilState(renderPipelines->getDepthStencilState(DepthStencilType::GBuffer));
    renderCommandEncoder->setStencilReferenceValue(128);
    renderCommandEncoder->setVertexBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    renderCommandEncoder->setFragmentBuffer(frameDataBuffer, 0, BufferIndexFrameData);

    drawMeshes(renderCommandEncoder, meshes, frameDataBuffer);
    renderCommandEncoder->popDebugGroup();
}

void RenderPassManager::drawFinalGathering(MTL::RenderCommandEncoder* renderCommandEncoder, MTL::Buffer*& frameDataBuffer) {

    bool doBilinear = editor->debug.debugCascadeLevel == -1;
    bool drawSky = editor->debug.sky;
    if (!resourceManager->getTexture(TextureName::FinalGatherTexture) ||
        !resourceManager->getTexture(TextureName::NormalGBuffer) || 
        !resourceManager->getTexture(TextureName::AlbedoGBuffer) || 
        !resourceManager->getTexture(TextureName::LinearDepthTexture)) {
        std::cerr << "Error: Missing textures for final gathering pass" << std::endl;
        return;
    }
    
    renderCommandEncoder->setCullMode(MTL::CullModeNone);

    renderCommandEncoder->setRenderPipelineState(renderPipelines->getRenderPipeline(RenderPipelineType::FinalGather));
    renderCommandEncoder->setVertexBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    renderCommandEncoder->setFragmentBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    
    renderCommandEncoder->setFragmentTexture(resourceManager->getTexture(TextureName::FinalGatherTexture), TextureIndexRadiance);
    renderCommandEncoder->setFragmentTexture(resourceManager->getTexture(TextureName::LinearDepthTexture), TextureIndexDepthTexture);
    renderCommandEncoder->setFragmentTexture(resourceManager->getTexture(TextureName::NormalGBuffer), TextureIndexNormal);
    renderCommandEncoder->setFragmentTexture(resourceManager->getTexture(TextureName::AlbedoGBuffer), TextureIndexBaseColor);
    renderCommandEncoder->setFragmentBytes(&doBilinear, sizeof(bool), 3);
    renderCommandEncoder->setFragmentBytes(&drawSky, sizeof(bool), 4);

    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, 0, 3, 1);
}

void RenderPassManager::drawDepthPrepass(MTL::CommandBuffer* commandBuffer, const std::vector<Mesh*>& meshes, MTL::Buffer*& frameDataBuffer) {
    if (!resourceManager->getTexture(TextureName::LinearDepthTexture) ||
        !resourceManager->getTexture(TextureName::DepthStencilTexture)) {
        std::cerr << "Error: Missing textures for depth prepass" << std::endl;
        return;
    }
    
    // Create a temporary render pass descriptor
    MTL::RenderPassDescriptor* depthPrepassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    depthPrepassDescriptor->colorAttachments()->object(0)->setTexture(resourceManager->getTexture(TextureName::LinearDepthTexture));
    depthPrepassDescriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadActionClear);
    depthPrepassDescriptor->colorAttachments()->object(0)->setStoreAction(MTL::StoreActionStore);
    depthPrepassDescriptor->colorAttachments()->object(0)->setClearColor(MTL::ClearColor(1.0, 1.0, 1.0, 1.0)); // Far depth

    // Set up the depth/stencil attachment for z-buffer
    depthPrepassDescriptor->depthAttachment()->setTexture(resourceManager->getTexture(TextureName::DepthStencilTexture));
    depthPrepassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionClear);
    depthPrepassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionStore);
    depthPrepassDescriptor->depthAttachment()->setClearDepth(1.0);

    // Also set up the stencil attachment since we're using a combined depth/stencil texture
    depthPrepassDescriptor->stencilAttachment()->setTexture(resourceManager->getTexture(TextureName::DepthStencilTexture));
    depthPrepassDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionClear);
    depthPrepassDescriptor->stencilAttachment()->setStoreAction(MTL::StoreActionStore);
    depthPrepassDescriptor->stencilAttachment()->setClearStencil(0);
    
    MTL::RenderCommandEncoder* depthPrepassEncoder = commandBuffer->renderCommandEncoder(depthPrepassDescriptor);
    depthPrepassEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    depthPrepassEncoder->setLabel(NS::String::string("Depth Prepass", NS::ASCIIStringEncoding));
    
    depthPrepassEncoder->setCullMode(MTL::CullModeBack);
    depthPrepassEncoder->setDepthStencilState(renderPipelines->getDepthStencilState(DepthStencilType::DepthPrepass));
    depthPrepassEncoder->setRenderPipelineState(renderPipelines->getRenderPipeline(RenderPipelineType::DepthPrepass));
    depthPrepassEncoder->setVertexBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    depthPrepassEncoder->setFragmentBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    
    // Render all meshes to depth buffer
    for (int i = 0; i < meshes.size(); i++) {
        depthPrepassEncoder->setVertexBuffer(meshes[i]->vertexBuffer, 0, BufferIndexVertexData);
        
        matrix_float4x4 modelMatrix = meshes[i]->getTransformMatrix();
        depthPrepassEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), BufferIndexVertexBytes);
        
        depthPrepassEncoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, meshes[i]->indexCount, MTL::IndexTypeUInt32, meshes[i]->indexBuffer, 0);
    }
    
    depthPrepassEncoder->endEncoding();
    depthPrepassDescriptor->release();
}

void RenderPassManager::drawDebug(MTL::RenderCommandEncoder* commandEncoder, MTL::CommandBuffer* commandBuffer) {
    commandEncoder->setRenderPipelineState(renderPipelines->getRenderPipeline(RenderPipelineType::ForwardDebug));

    commandEncoder->setVertexBuffer(debug->lineBuffer, 0, 0);
    
    // Assuming the frameDataBuffer is the latest one in the frame
    std::string labelStr = "FrameData" + std::to_string(0);
    MTL::Buffer* frameDataBuffer = resourceManager->getBufferByName(labelStr);
    commandEncoder->setVertexBuffer(frameDataBuffer, 0, BufferIndexFrameData);

    uint32_t* lineCount = reinterpret_cast<uint32_t*>(debug->lineCountBuffer->contents());
    
    if (lineCount != nil && *lineCount > 0 && editor->debug.enableDebugFeature) {
         commandEncoder->drawPrimitives(MTL::PrimitiveTypeLine, 0, *lineCount * 2, 1);
    }
    editor->endFrame(commandBuffer, commandEncoder);
}

void RenderPassManager::dispatchRaytracing(MTL::CommandBuffer* commandBuffer, MTL::Buffer*& frameDataBuffer, const std::vector<MTL::Buffer*>& cascadeBuffers) {
    if (!resourceManager->getTexture(TextureName::FinalGatherTexture) ||
        !resourceManager->getTexture(TextureName::LinearDepthTexture)) {
        std::cerr << "Error: Missing textures for ray tracing dispatch" << std::endl;
        return;
    }
    
    uint width = uint(resourceManager->getTexture(TextureName::FinalGatherTexture)->width());
    uint height = uint(resourceManager->getTexture(TextureName::FinalGatherTexture)->height());
    
    // Create ping-pong textures for cascades
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setTextureType(MTL::TextureType2D);
    desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setStorageMode(MTL::StorageModeShared);
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    MTL::Texture* rcRenderTargets[2];
    std::string labelStr = "Render Target" + std::to_string(0);
    NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
    rcRenderTargets[0] = device->newTexture(desc);
    rcRenderTargets[0]->setLabel(label);
    
    labelStr = "Render Target" + std::to_string(1);
    label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
    rcRenderTargets[1] = device->newTexture(desc);
    rcRenderTargets[1]->setLabel(label);
    
    MTL::Texture* lastMergedTexture = nil;
    int pingPongIndex = 0;
    
    int startLevel = MAX_CASCADE_LEVEL - 1;
    int endLevel = (editor->debug.debugCascadeLevel == -1) ? 0 : editor->debug.debugCascadeLevel;

    for (int level = startLevel; level >= endLevel; --level) {
        MTL::ComputeCommandEncoder* computeEncoder = commandBuffer->computeCommandEncoder();
        computeEncoder->setLabel(NS::String::string(("Ray Tracing Cascade " + std::to_string(level)).c_str(), NS::ASCIIStringEncoding));
        
        // Update cascade level in frame data
        CascadeData *cascadeData = reinterpret_cast<CascadeData*>(cascadeBuffers[level]->contents());
        cascadeData->cascadeLevel = level;
        cascadeData->probeSpacing = PROBE_SPACING;
        cascadeData->intervalLength = editor->debug.intervalLength;
        cascadeData->maxCascade = MAX_CASCADE_LEVEL - 1;
        cascadeData->enableSky = editor->debug.sky ? 1.0 : 0.0;
        cascadeData->enableSun = editor->debug.sun ? 1.0 : 0.0;
        
        MTL::Texture* currentRenderTarget = nil;
        
        if (level == MAX_CASCADE_LEVEL - 1 && (editor->debug.debugCascadeLevel == -1 ? 0 : editor->debug.debugCascadeLevel) != MAX_CASCADE_LEVEL - 1) {
            currentRenderTarget = rcRenderTargets[pingPongIndex];
            pingPongIndex = 1 - pingPongIndex;
            lastMergedTexture = nil;
        } else if (level > (editor->debug.debugCascadeLevel == -1 ? 0 : editor->debug.debugCascadeLevel)) {
            currentRenderTarget = rcRenderTargets[pingPongIndex];
            pingPongIndex = 1 - pingPongIndex;
        } else {
            currentRenderTarget = resourceManager->getTexture(TextureName::FinalGatherTexture);
        }
        
        computeEncoder->setComputePipelineState(renderPipelines->getComputePipeline(ComputePipelineType::Raytracing));
        computeEncoder->setTexture(currentRenderTarget, TextureIndexRadiance);
        
        if (level < MAX_CASCADE_LEVEL - 1) {
            computeEncoder->setTexture(lastMergedTexture, TextureIndexRadianceUpper);
            computeEncoder->useResource(lastMergedTexture, MTL::ResourceUsageRead);
        }
        if (level == endLevel) {
            computeEncoder->setTexture(resourceManager->getTexture(TextureName::HistoryTexture), TextureIndexHistory);
            computeEncoder->useResource(resourceManager->getTexture(TextureName::HistoryTexture), MTL::ResourceUsageRead);
        }
        
        labelStr = "Frame" + std::to_string(0) + "CascadeProbes" + std::to_string(level);
        MTL::Buffer* probeBuffer = resourceManager->getBufferByName(labelStr);
        labelStr = "Frame" + std::to_string(0) + "CascadeRays" + std::to_string(level);
        MTL::Buffer* rayBuffer = resourceManager->getBufferByName(labelStr);
        
        // For debugging
        if (CREATE_DEBUG_DATA) {
            computeEncoder->setBuffer(probeBuffer, 0, BufferIndexProbeData);
            computeEncoder->setBuffer(rayBuffer, 0, BufferIndexProbeRayData);
            computeEncoder->useResource(probeBuffer, MTL::ResourceUsageWrite);
            computeEncoder->useResource(rayBuffer, MTL::ResourceUsageWrite);
        }
        
        labelStr = "FrameData" + std::to_string(0);
        MTL::Buffer* frameData = resourceManager->getBufferByName(labelStr);
        labelStr = "Frame" + std::to_string(0) + "CascadeData" + std::to_string(level);
        MTL::Buffer* cascadeBuffer = resourceManager->getBufferByName(labelStr);
        
        computeEncoder->setBuffer(frameData, 0, BufferIndexFrameData);
        computeEncoder->setBuffer(cascadeBuffer, 0, BufferIndexCascadeData);
        
        // Get the resource buffer from RayTracingManager
        MTL::Buffer* resourceBuffer = rayTracingManager->getResourceBuffer();
        computeEncoder->setBuffer(resourceBuffer, 0, BufferIndexResources);
        
        computeEncoder->setTexture(resourceManager->getTexture(TextureName::LinearDepthTexture), TextureIndexDepthTexture);

        computeEncoder->useResource(resourceBuffer, MTL::ResourceUsageRead);
        computeEncoder->useResource(resourceManager->getTexture(TextureName::LinearDepthTexture), MTL::ResourceUsageRead);
        computeEncoder->useResource(currentRenderTarget, MTL::ResourceUsageWrite);

        // Set acceleration structures from RayTracingManager
        MTL::AccelerationStructure* accelStructure = rayTracingManager->getPrimitiveAccelerationStructure();
        if (!accelStructure) {
            std::cerr << "Error: Acceleration structure is null when dispatching raytracing!" << std::endl;
            return;
        }
        
        computeEncoder->setAccelerationStructure(accelStructure, BufferIndexAccelerationStructure);
        computeEncoder->useResource(accelStructure, MTL::ResourceUsageRead);

        // Compute probe grid and thread counts
        int tile_size = PROBE_SPACING * (1 << level);
        size_t probeGridSizeX = (width + tile_size - 1) / tile_size;
        size_t probeGridSizeY = (height + tile_size - 1) / tile_size;
        uint raysPerDim = (1 << (level + 2));
        uint numRays = (raysPerDim * raysPerDim);
        size_t totalProbes = probeGridSizeX * probeGridSizeY;
        size_t totalThreads = totalProbes * numRays;

        MTL::Size threadGroupSize = MTL::Size(64, 1, 1);
        size_t numThreadGroups = (totalThreads + threadGroupSize.width - 1) / threadGroupSize.width;

        computeEncoder->dispatchThreadgroups(MTL::Size(numThreadGroups, 1, 1), threadGroupSize);
        computeEncoder->endEncoding();
                
        if (level > 0) {
            lastMergedTexture = currentRenderTarget;
        }
    }
    
    // Copy last result to history
    MTL::BlitCommandEncoder* blitEncoder = commandBuffer->blitCommandEncoder();
    MTL::Origin origin = MTL::Origin(0, 0, 0);
    MTL::Size size = MTL::Size(width, height, 1);
    blitEncoder->copyFromTexture(resourceManager->getTexture(TextureName::FinalGatherTexture), 0, 0, origin, size, resourceManager->getTexture(TextureName::HistoryTexture), 0, 0, origin);
    blitEncoder->endEncoding();
    
    // Clean up temporary textures
    desc->release();
    rcRenderTargets[0]->release();
    rcRenderTargets[1]->release();
}

void RenderPassManager::dispatchTwoPassBlur(MTL::CommandBuffer* commandBuffer, MTL::Buffer*& frameDataBuffer) {
    // Use enum-based texture lookups
    
    // Make sure textures exist
    if (!resourceManager->getTexture(TextureName::FinalGatherTexture) || 
        !resourceManager->getTexture(TextureName::IntermediateBlurTexture) || 
        !resourceManager->getTexture(TextureName::BlurredColorTexture)) {
        std::cerr << "Error: Missing textures for two-pass blur" << std::endl;
        return;
    }
    
    uint width = uint(resourceManager->getTexture(TextureName::FinalGatherTexture)->width());
    uint height = uint(resourceManager->getTexture(TextureName::FinalGatherTexture)->height());
    
    MTL::Size threadGroupSize = MTL::Size(16, 16, 1);
    MTL::Size threadgroups = MTL::Size((width + threadGroupSize.width - 1) / threadGroupSize.width,
                                     (height + threadGroupSize.height - 1) / threadGroupSize.height, 1);
    
    // First pass - Horizontal blur
    MTL::ComputeCommandEncoder* horizontalEncoder = commandBuffer->computeCommandEncoder();
    horizontalEncoder->setLabel(NS::String::string("Horizontal Blur", NS::ASCIIStringEncoding));
    horizontalEncoder->setComputePipelineState(renderPipelines->getComputePipeline(ComputePipelineType::HorizontalBlur));
    
    horizontalEncoder->setBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    horizontalEncoder->setTexture(resourceManager->getTexture(TextureName::FinalGatherTexture), TextureIndexRadianceUpper);
    horizontalEncoder->setTexture(resourceManager->getTexture(TextureName::IntermediateBlurTexture), TextureIndexRadiance);
    
    horizontalEncoder->useResource(resourceManager->getTexture(TextureName::FinalGatherTexture), MTL::ResourceUsageRead);
    horizontalEncoder->useResource(resourceManager->getTexture(TextureName::IntermediateBlurTexture), MTL::ResourceUsageWrite);
    
    horizontalEncoder->dispatchThreadgroups(threadgroups, threadGroupSize);
    horizontalEncoder->endEncoding();
    
    // Second pass - Vertical blur
    MTL::ComputeCommandEncoder* verticalEncoder = commandBuffer->computeCommandEncoder();
    verticalEncoder->setLabel(NS::String::string("Vertical Blur", NS::ASCIIStringEncoding));
    verticalEncoder->setComputePipelineState(renderPipelines->getComputePipeline(ComputePipelineType::VerticalBlur));
    
    verticalEncoder->setBuffer(frameDataBuffer, 0, BufferIndexFrameData);
    verticalEncoder->setTexture(resourceManager->getTexture(TextureName::IntermediateBlurTexture), TextureIndexRadianceUpper);
    verticalEncoder->setTexture(resourceManager->getTexture(TextureName::BlurredColorTexture), TextureIndexRadiance);
    
    verticalEncoder->useResource(resourceManager->getTexture(TextureName::IntermediateBlurTexture), MTL::ResourceUsageRead);
    verticalEncoder->useResource(resourceManager->getTexture(TextureName::BlurredColorTexture), MTL::ResourceUsageWrite);
    
    verticalEncoder->dispatchThreadgroups(threadgroups, threadGroupSize);
    verticalEncoder->endEncoding();
}

void RenderPassManager::dispatchMinMaxDepthMipmaps(MTL::CommandBuffer* commandBuffer) {
    MTL::Texture* minMaxDepthTex = resourceManager->getTexture(TextureName::MinMaxDepthTexture);
    
    // Make sure textures exist
    if (!resourceManager->getTexture(TextureName::DepthStencilTexture) || 
        !minMaxDepthTex) {
        std::cerr << "Error: Missing textures for min/max depth mipmaps" << std::endl;
        return;
    }
    
    MTL::ComputeCommandEncoder* encoder = commandBuffer->computeCommandEncoder();
    {
        encoder->setLabel(NS::String::string("First Min Max Depth", NS::ASCIIStringEncoding));
        encoder->setComputePipelineState(renderPipelines->getComputePipeline(ComputePipelineType::InitMinMaxDepth));

        encoder->setTexture(resourceManager->getTexture(TextureName::DepthStencilTexture), 0);
        encoder->setTexture(minMaxDepthTex, 1);

        MTL::Size threadsPerGroup(8, 8, 1);
        MTL::Size threadgroups((minMaxDepthTex->width() + 7) / 8, (minMaxDepthTex->height() + 7) / 8, 1);

        encoder->dispatchThreadgroups(threadgroups, threadsPerGroup);
    }
    
    encoder->setLabel(NS::String::string("Min Max Depth", NS::ASCIIStringEncoding));
    encoder->setComputePipelineState(renderPipelines->getComputePipeline(ComputePipelineType::MinMaxDepth));

    unsigned long mipLevels = minMaxDepthTex->mipmapLevelCount();

    for (uint32_t level = 1; level < mipLevels; ++level) {
        std::string labelStr = "MipLevel: " + std::to_string(level-1);
        NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
        
        encoder->pushDebugGroup(label);
        NS::Range levelRangeSrc(level - 1, 1);
        NS::Range levelRangeDst(level, 1);
        NS::Range sliceRange(0, 1);

        MTL::Texture* srcMip = minMaxDepthTex->newTextureView(
            MTL::PixelFormatRG32Float,
            MTL::TextureType2D,
            levelRangeSrc,
            sliceRange
        );

        MTL::Texture* dstMip = minMaxDepthTex->newTextureView(
            MTL::PixelFormatRG32Float,
            MTL::TextureType2D,
            levelRangeDst,
            sliceRange
        );
        
        srcMip->setLabel(label);
        dstMip->setLabel(label);

        encoder->setTexture(srcMip, 0);
        encoder->setTexture(dstMip, 1);

        MTL::Size threadsPerGroup(8, 8, 1);
        MTL::Size threadgroups((dstMip->width() + 7) / 8, (dstMip->height() + 7) / 8, 1);

        encoder->dispatchThreadgroups(threadgroups, threadsPerGroup);

        srcMip->release();
        dstMip->release();
        
        encoder->popDebugGroup();
    }

    encoder->endEncoding();
}
