#include "engine.hpp"

Engine::Engine()
: camera(simd::float3{7.0f, 5.0f, 0.0f}, NEAR_PLANE, FAR_PLANE)
, lastFrame(0.0f)
, frameNumber(0)
, currentFrameIndex(0)
, totalTriangles(0) {
	inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);

    for (int i = 0; i < MaxFramesInFlight; i++) {
        frameSemaphores[i] = dispatch_semaphore_create(1);
    }
}

void Engine::init() {
    initDevice();
    initWindow();

    resourceManager = std::make_unique<ResourceManager>(metalDevice);
    editor = std::make_unique<Editor>(glfwWindow, metalDevice);
    debug = std::make_unique<Debug>(metalDevice);
    rayTracingManager = std::make_unique<RayTracingManager>(metalDevice, resourceManager.get());


    createCommandQueue();
	loadScene();
    createDefaultLibrary();
    createBuffers();
    renderPipelines.initialize(metalDevice, metalDefaultLibrary);
    defaultVertexDescriptor = createDefaultVertexDescriptor();
    createRenderPipelines();
	createViewRenderPassDescriptor();
    // createAccelerationStructureWithDescriptors();
    // setupTriangleResources();
    rayTracingManager->setupAccelerationStructures(meshes);
    rayTracingManager->setupTriangleResources(meshes);
}

void Engine::run() {
    while (!glfwWindowShouldClose(glfwWindow)) {
        float currentFrame = glfwGetTime();
        float deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;
        
        camera.processKeyboardInput(glfwWindow, deltaTime);
        editor->debug.cameraPosition = camera.position;
        
        @autoreleasepool {
            metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
            draw();
        }
        
        glfwPollEvents();
    }
}

void Engine::cleanup() {
    glfwTerminate();
    
    // Clean up mesh objects
    for (auto& mesh : meshes) {
        delete mesh;
    }
    
    // Release frame-specific buffers that are not managed by ResourceManager
    for (int frame = 0; frame < MaxFramesInFlight; frame++) {
        // Will be moving these to ResourceManager eventually, but for now:
        for (int cascade = 0; cascade < CASCADE_LEVEL; cascade++) {
            if (cascadeDataBuffer[frame][cascade]) {
                cascadeDataBuffer[frame][cascade]->release();
            }
            
            if (createDebugData) {
                if (probePosBuffer[frame][cascade]) {
                    probePosBuffer[frame][cascade]->release();
                }
                if (rayBuffer[frame][cascade]) {
                    rayBuffer[frame][cascade]->release();
                }
            }
        }
    }
    
    // Release descriptors which aren't managed by ResourceManager
    if (viewRenderPassDescriptor) viewRenderPassDescriptor->release();
    if (finalGatherDescriptor) finalGatherDescriptor->release();
    if (forwardDescriptor) forwardDescriptor->release();
    if (depthPrepassDescriptor) depthPrepassDescriptor->release();
    
    // Release other Metal objects
    if (defaultVertexDescriptor) defaultVertexDescriptor->release();
    if (metalCommandQueue) metalCommandQueue->release();
    
    // Use ResourceManager to release all resources it manages
    if (resourceManager) {
        resourceManager->releaseAllResources();
    }
    
    // Finally release the device
    if (metalDevice) {
        metalDevice->release();
    }
}

void Engine::initDevice() {
    metalDevice = MTL::CreateSystemDefaultDevice();
}

void Engine::frameBufferSizeCallback(GLFWwindow *window, int width, int height) {
    Engine* engine = (Engine*)glfwGetWindowUserPointer(window);
    engine->resizeFrameBuffer(width, height);
}

void Engine::mouseButtonCallback(GLFWwindow* window, int button, int action, int mods) {
    Engine* engine = (Engine*)glfwGetWindowUserPointer(window);
    engine->camera.processMouseButton(window, button, action);
}

void Engine::cursorPosCallback(GLFWwindow* window, double xpos, double ypos) {
    Engine* engine = (Engine*)glfwGetWindowUserPointer(window);
    engine->camera.processMouseMovement(xpos, ypos);
}

void Engine::resizeFrameBuffer(int width, int height) {
    metalLayer.drawableSize = CGSizeMake(width, height);
    
    resourceManager->releaseTexture(albedoSpecularGBuffer);
    resourceManager->releaseTexture(normalMapGBuffer);
    resourceManager->releaseTexture(depthGBuffer);
    resourceManager->releaseTexture(depthStencilTexture);
    resourceManager->releaseTexture(finalGatherTexture);
    resourceManager->releaseTexture(forwardDepthStencilTexture);
    resourceManager->releaseTexture(linearDepthTexture);
    resourceManager->releaseTexture(minMaxDepthTexture);
    resourceManager->releaseTexture(intermediateBlurTexture);
    resourceManager->releaseTexture(blurredColor);
    
    // Release render pass descriptors
    if (viewRenderPassDescriptor) {
        viewRenderPassDescriptor->release();
        viewRenderPassDescriptor = nil;
    }
    if (finalGatherDescriptor) {
        finalGatherDescriptor->release();
        finalGatherDescriptor = nil;
    }
    if (forwardDescriptor) {
        forwardDescriptor->release();
        forwardDescriptor = nil;
    }
    if (depthPrepassDescriptor) {
        depthPrepassDescriptor->release();
        depthPrepassDescriptor = nil;
    }

    // Recreate G-buffer textures and descriptors
    createViewRenderPassDescriptor();
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
    updateRenderPassDescriptor();
}

void Engine::initWindow() {
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindow = glfwCreateWindow(1920, 1152, "Metalλαγμένος", NULL, NULL);
    if (!glfwWindow) {
        glfwTerminate();
        exit(EXIT_FAILURE);
    }

    int width, height;
    glfwGetFramebufferSize(glfwWindow, &width, &height);

    metalWindow = glfwGetCocoaWindow(glfwWindow);
    metalLayer = [CAMetalLayer layer];
    metalLayer.device = (__bridge id<MTLDevice>)metalDevice;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.drawableSize = CGSizeMake(width, height);
    metalWindow.contentView.layer = metalLayer;
    metalWindow.contentView.wantsLayer = YES;
    metalLayer.framebufferOnly = false;

    glfwSetWindowUserPointer(glfwWindow, this);
    glfwSetFramebufferSizeCallback(glfwWindow, frameBufferSizeCallback);
    glfwSetMouseButtonCallback(glfwWindow, mouseButtonCallback);
    glfwSetCursorPosCallback(glfwWindow, cursorPosCallback);
    lastFrame = glfwGetTime();
    
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
}

MTL::CommandBuffer* Engine::beginFrame(bool isPaused) {
    // Wait on the semaphore for the current frame
    dispatch_semaphore_wait(frameSemaphores[currentFrameIndex], DISPATCH_TIME_FOREVER);

	MTL::CommandBuffer* commandBuffer = metalCommandQueue->commandBuffer();
	
	MTL::CommandBufferHandler handler = [this](MTL::CommandBuffer*) {
		// Signal the semaphore for this frame when GPU work is complete
		dispatch_semaphore_signal(frameSemaphores[currentFrameIndex]);
	};
	commandBuffer->addCompletedHandler(handler);
    
    updateWorldState(isPaused);
	
	return commandBuffer;
}

void Engine::endFrame(MTL::CommandBuffer* commandBuffer) {
    if(commandBuffer) {
        commandBuffer->presentDrawable(metalDrawable);
        commandBuffer->commit();
        
        if (frameNumber == 100 && createDebugData) {
            createSphereGrid();
            createDebugLines();
        }
        
        // Move to next frame
        currentFrameIndex = (currentFrameIndex + 1) % MaxFramesInFlight;
    }
}

void Engine::loadSceneFromJSON(const std::string& jsonFilePath) {
    if (!defaultVertexDescriptor) {
        defaultVertexDescriptor = createDefaultVertexDescriptor();
    }
    
    SceneParser parser(metalDevice, defaultVertexDescriptor);
    
    std::vector<Mesh*> loadedMeshes = parser.loadScene(jsonFilePath);
    
    meshes.insert(meshes.end(), loadedMeshes.begin(), loadedMeshes.end());
}

void Engine::loadScene() {
    loadSceneFromJSON(std::string(SCENES_PATH) + "/sponza.json");
}

MTL::VertexDescriptor* Engine::createDefaultVertexDescriptor() {
    MTL::VertexDescriptor* vertexDescriptor = MTL::VertexDescriptor::alloc()->init();
    
    // Position attribute
    vertexDescriptor->attributes()->object(VertexAttributePosition)->setFormat(MTL::VertexFormatFloat4);
    vertexDescriptor->attributes()->object(VertexAttributePosition)->setOffset(offsetof(Vertex, position));
    vertexDescriptor->attributes()->object(VertexAttributePosition)->setBufferIndex(0);
    
    // Normal attribute
    vertexDescriptor->attributes()->object(VertexAttributeNormal)->setFormat(MTL::VertexFormatFloat4);
    vertexDescriptor->attributes()->object(VertexAttributeNormal)->setOffset(offsetof(Vertex, normal));
    vertexDescriptor->attributes()->object(VertexAttributeNormal)->setBufferIndex(0);
    
    // IMPORTANT: Always include all attributes for pipeline creation, even for non-textured meshes
    // The function constants will handle their usage in the shader
    
    // Texture coordinate attribute
    vertexDescriptor->attributes()->object(VertexAttributeTexcoord)->setFormat(MTL::VertexFormatFloat2);
    vertexDescriptor->attributes()->object(VertexAttributeTexcoord)->setOffset(offsetof(Vertex, textureCoordinate));
    vertexDescriptor->attributes()->object(VertexAttributeTexcoord)->setBufferIndex(0);
    
    // Tangent attribute
    vertexDescriptor->attributes()->object(VertexAttributeTangent)->setFormat(MTL::VertexFormatFloat4);
    vertexDescriptor->attributes()->object(VertexAttributeTangent)->setOffset(offsetof(Vertex, tangent));
    vertexDescriptor->attributes()->object(VertexAttributeTangent)->setBufferIndex(0);
    
    // Bitangent attribute
    vertexDescriptor->attributes()->object(VertexAttributeBitangent)->setFormat(MTL::VertexFormatFloat4);
    vertexDescriptor->attributes()->object(VertexAttributeBitangent)->setOffset(offsetof(Vertex, bitangent));
    vertexDescriptor->attributes()->object(VertexAttributeBitangent)->setBufferIndex(0);
    
    // DiffuseTextureIndex
    vertexDescriptor->attributes()->object(VertexAttributeDiffuseIndex)->setFormat(MTL::VertexFormatInt);
    vertexDescriptor->attributes()->object(VertexAttributeDiffuseIndex)->setOffset(offsetof(Vertex, diffuseTextureIndex));
    vertexDescriptor->attributes()->object(VertexAttributeDiffuseIndex)->setBufferIndex(0);
    
    // NormalTextureIndex
    vertexDescriptor->attributes()->object(VertexAttributeNormalIndex)->setFormat(MTL::VertexFormatInt);
    vertexDescriptor->attributes()->object(VertexAttributeNormalIndex)->setOffset(offsetof(Vertex, normalTextureIndex));
    vertexDescriptor->attributes()->object(VertexAttributeNormalIndex)->setBufferIndex(0);
    
    // Set layout
    vertexDescriptor->layouts()->object(0)->setStride(sizeof(Vertex));
    vertexDescriptor->layouts()->object(0)->setStepRate(1);
    vertexDescriptor->layouts()->object(0)->setStepFunction(MTL::VertexStepFunctionPerVertex);
    
    return vertexDescriptor;
}

void Engine::createDefaultLibrary() {
    // Create an NSString from the metallib path
    NS::String* libraryPath = NS::String::string(
        SHADER_METALLIB,
        NS::UTF8StringEncoding
    );
    
    NS::Error* error = nullptr;

    printf("Selected Device: %s\n", metalDevice->name()->utf8String());
    
    metalDefaultLibrary = metalDevice->newLibrary(libraryPath, &error);
    
    if (!metalDefaultLibrary) {
        std::cerr << "Failed to load metal library at path: " << SHADER_METALLIB;
        if (error) {
            std::cerr << "\nError: " << error->localizedDescription()->utf8String();
        }
        std::exit(-1);
    }
}

void Engine::createBuffers() {
    cascadeDataBuffer.resize(MaxFramesInFlight);
    probePosBuffer.resize(MaxFramesInFlight);
    rayBuffer.resize(MaxFramesInFlight);
    
    for (int frame = 0; frame < MaxFramesInFlight; frame++) {
        // Use ResourceManager to create frame data buffers
        frameDataBuffers[frame] = resourceManager->createBuffer(
            sizeof(FrameData), 
            nullptr, 
            MTL::ResourceStorageModeShared, 
            "FrameData"
        );
        
        cascadeDataBuffer[frame].resize(CASCADE_LEVEL);
        probePosBuffer[frame].resize(CASCADE_LEVEL);
        rayBuffer[frame].resize(CASCADE_LEVEL);
        
        for (int cascade = 0; cascade < CASCADE_LEVEL; cascade++) {
            std::string labelStr = "Frame: " + std::to_string(frame) + "|CascadeData: " + std::to_string(cascade);
            
            cascadeDataBuffer[frame][cascade] = resourceManager->createBuffer(
                sizeof(CascadeData), 
                nullptr, 
                MTL::ResourceStorageModeShared, 
                labelStr.c_str()
            );

            if (createDebugData) {
                debugProbeCount = floor(metalLayer.drawableSize.width / (PROBE_SPACING * 1 << cascade)) * 
                                  floor(metalLayer.drawableSize.height / (PROBE_SPACING * 1 << cascade));
                size_t probeBufferSize = debugProbeCount * sizeof(Probe);
                rayCount = debugProbeCount * BASE_RAY * (1 << (2 * cascade));
                size_t rayBufferSize = rayCount * sizeof(ProbeRay);
                
                labelStr = "Frame: " + std::to_string(frame) + "|CascadeProbes: " + std::to_string(cascade);
                probePosBuffer[frame][cascade] = resourceManager->createBuffer(
                    probeBufferSize, 
                    nullptr, 
                    MTL::ResourceStorageModeShared, 
                    "probePosBuffer"
                );
                
                labelStr = "Frame: " + std::to_string(frame) + "|CascadeRays: " + std::to_string(cascade);
                rayBuffer[frame][cascade] = resourceManager->createBuffer(
                    rayBufferSize, 
                    nullptr, 
                    MTL::ResourceStorageModeShared, 
                    "rayBuffer"
                );
            }
        }
    }
}

void printMatrix(const matrix_float4x4& matrix) {
    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < 4; ++j) {
            std::cout << matrix.columns[j][i] << " ";
        }
        std::cout << std::endl;
    }
}

void Engine::updateWorldState(bool isPaused) {
	if (!isPaused) {
		frameNumber++;
	}

	FrameData *frameData = (FrameData *)(frameDataBuffers[currentFrameIndex]->contents());

	float aspectRatio = metalDrawable->layer()->drawableSize().width / metalDrawable->layer()->drawableSize().height;
	
	camera.setProjectionMatrix(45, aspectRatio, NEAR_PLANE, FAR_PLANE);
	frameData->projection_matrix = camera.getProjectionMatrix();
	frameData->projection_matrix_inverse = matrix_invert(frameData->projection_matrix);
	frameData->view_matrix = camera.getViewMatrix();
    frameData->view_matrix_inverse = camera.getInverseViewMatrix();
    
    frameData->cameraUp         = float4{camera.up.x,       camera.up.y,        camera.up.z, 1.0f};
    frameData->cameraRight      = float4{camera.right.x,    camera.right.y,     camera.right.z, 1.0f};
    frameData->cameraForward    = float4{camera.front.x,    camera.front.y,     camera.front.z, 1.0f};
    frameData->cameraPosition   = float4{camera.position.x, camera.position.y,  camera.position.z, 1.0f};

	// Set screen dimensions
	frameData->framebuffer_width = (uint)metalLayer.drawableSize.width;
	frameData->framebuffer_height = (uint)metalLayer.drawableSize.height;
    frameData->near_plane = NEAR_PLANE;
    frameData->far_plane = FAR_PLANE;

	// Define the sun color
	frameData->sun_color = simd_make_float4(0.95, 0.95, 0.9, 1.0);
	frameData->sun_specular_intensity = 0.7;

	// Calculate the sun's X position oscillating over time
	float oscillationSpeed = 0.02f;
	float oscillationAmplitude = 9.0f;
	float sunZ = sin(frameNumber * oscillationSpeed) * oscillationAmplitude;

	float sunY = 10.0f;
	float sunX = 0.0f;

	// Sun world position
	float4 sunWorldPosition = {sunX, sunY, sunZ, 1.0};
	float4 sunWorldDirection = -sunWorldPosition;

	// Update the sun direction in view space
	frameData->sun_eye_direction = sunWorldDirection;

	float4 directionalLightUpVector = {0.0, 1.0, 0.0, 0.0};
	// Update scene matrices
	frameData->scene_model_matrix = matrix4x4_translation(0.0f, 0.0f, 0.0f); // Sponza at origin
	frameData->scene_modelview_matrix = frameData->view_matrix * frameData->scene_model_matrix;
	frameData->scene_normal_matrix = matrix3x3_upper_left(frameData->scene_model_matrix);
}

void Engine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void Engine::createRenderPipelines() {
    NS::Error* error;
	
	albedoSpecularGBufferFormat = MTL::PixelFormatRGBA8Unorm_sRGB;
	normalMapGBufferFormat 	    = MTL::PixelFormatRGBA8Snorm;
	depthGBufferFormat			= MTL::PixelFormatR32Float;

    #pragma mark Deferred render pipeline setup
    {
		{
			RenderPipelineConfig gbufferConfig{
                .label = "G-buffer Creation",
                .vertexFunctionName = "gbuffer_vertex",
                .fragmentFunctionName = "gbuffer_fragment",
                .vertexDescriptor = defaultVertexDescriptor
            };
            gbufferConfig.colorAttachments = {
                {RenderTargetAlbedo, albedoSpecularGBufferFormat},
                {RenderTargetNormal, normalMapGBufferFormat},
                {RenderTargetDepth, depthGBufferFormat}
            };
            
            // Create the function constant object
            static NS::String* hasTexturesID = NS::String::string("hasTextures", NS::ASCIIStringEncoding);
            MTL::FunctionConstantValues* hasTexturesTrue = MTL::FunctionConstantValues::alloc()->init();
            bool trueValue = true;
            hasTexturesTrue->setConstantValue(&trueValue, MTL::DataTypeBool, hasTexturesID);

            MTL::FunctionConstantValues* hasTexturesFalse = MTL::FunctionConstantValues::alloc()->init();
            bool falseValue = false;
            hasTexturesFalse->setConstantValue(&falseValue, MTL::DataTypeBool, hasTexturesID);

            // Create pipelines for both cases
            RenderPipelineConfig gbufferTexturedConfig = gbufferConfig;
            gbufferTexturedConfig.functionConstants = hasTexturesTrue;
            renderPipelines.createRenderPipeline(RenderPipelineType::GBufferTextured, gbufferTexturedConfig);

            RenderPipelineConfig gbufferNonTexturedConfig = gbufferConfig;
            gbufferNonTexturedConfig.functionConstants = hasTexturesFalse;
            renderPipelines.createRenderPipeline(RenderPipelineType::GBufferNonTextured, gbufferNonTexturedConfig);
            
            RenderPipelineConfig depthPrepassConfig{
                .label = "Depth Prepass",
                .vertexFunctionName = "depth_prepass_vertex",
                .fragmentFunctionName = "depth_prepass_fragment",
                .colorPixelFormat = MTL::PixelFormatR32Float,
                .depthPixelFormat = MTL::PixelFormatDepth32Float_Stencil8,
                .stencilPixelFormat = MTL::PixelFormatDepth32Float_Stencil8,
                .vertexDescriptor = defaultVertexDescriptor,
                .functionConstants = hasTexturesFalse
            };
            renderPipelines.createRenderPipeline(RenderPipelineType::DepthPrepass, depthPrepassConfig);
            
            // Create depth stencil state for depth prepass
            DepthStencilConfig depthPrepassDepthConfig{
                .label = "Depth Prepass Depth State",
                .depthCompareFunction = MTL::CompareFunctionLess,
                .depthWriteEnabled = true
            };
            renderPipelines.createDepthStencilState(DepthStencilType::DepthPrepass, depthPrepassDepthConfig);
		}
		
		#pragma mark GBuffer depth state setup
		{
		#if LIGHT_STENCIL_CULLING
			StencilConfig gbufferStencil{
                .stencilCompareFunction = MTL::CompareFunctionAlways,
                .stencilFailureOperation = MTL::StencilOperationKeep,
                .depthFailureOperation = MTL::StencilOperationKeep,
                .depthStencilPassOperation = MTL::StencilOperationReplace,
                .readMask = 0x0,
                .writeMask = 0xFF
            };
		#else
			StencilConfig gbufferStencil{};
		#endif
			DepthStencilConfig gbufferDepthConfig{
                .label = "G-buffer Creation",
                .depthCompareFunction = MTL::CompareFunctionLess,
                .depthWriteEnabled = true,
                .frontStencil = gbufferStencil,
                .backStencil = gbufferStencil
            };
            renderPipelines.createDepthStencilState(DepthStencilType::GBuffer, gbufferDepthConfig);
		}
		
		// Setup render state to apply the radiance light in final pass
		{
            #pragma mark Final gathering render pipeline setup
            {
                RenderPipelineConfig finalGatherConfig{
                    .label = "Final Gathering",
                    .vertexFunctionName = "final_gather_vertex",
                    .fragmentFunctionName = "final_gather_fragment",
                    .colorPixelFormat = metalDrawable->texture()->pixelFormat(),
                    .depthPixelFormat = MTL::PixelFormatInvalid,
                    .stencilPixelFormat = MTL::PixelFormatInvalid,
                    .vertexDescriptor = nullptr
                };
                renderPipelines.createRenderPipeline(RenderPipelineType::FinalGather, finalGatherConfig);
            }
		}
    }
    
    #pragma mark Ray tracing pipeline state
    {
        ComputePipelineConfig raytracingConfig{
            .label = "Raytracing Pipeline",
            .computeFunctionName = "raytracingKernel"
        };
        renderPipelines.createComputePipeline(ComputePipelineType::Raytracing, raytracingConfig);
    }
    
    #pragma mark Forward Debug pipeline state
    {
        RenderPipelineConfig debugConfig{
            .label = "Forward Debug Pipeline",
            .vertexFunctionName = "forwardVertex",
            .fragmentFunctionName = "forwardFragment",
            .colorPixelFormat = metalDrawable->texture()->pixelFormat()
        };
        renderPipelines.createRenderPipeline(RenderPipelineType::ForwardDebug, debugConfig);
    }
    
    #pragma mark Min Max Depth Buffer
    {
        #pragma mark Init Min Max Depth Buffer Pipeline state
        {
            ComputePipelineConfig initMinMaxDepthConfig{
                .label = "Init Min Max Depth Buffer",
                .computeFunctionName = "initMinMaxDepthKernel"
            };
            renderPipelines.createComputePipeline(ComputePipelineType::InitMinMaxDepth, initMinMaxDepthConfig);
        }
        
        #pragma mark Min Max Depth Buffer Pipeline state
        {
            ComputePipelineConfig minMaxDepthConfig{
                .label = "Min Max Depth Buffer",
                .computeFunctionName = "minMaxDepthKernel"
            };
            renderPipelines.createComputePipeline(ComputePipelineType::MinMaxDepth, minMaxDepthConfig);
        }
    }
    
    #pragma mark Two Pass Blur
    {
        ComputePipelineConfig verticalBlurConfig{
            .label = "Vertical Blur",
            .computeFunctionName = "verticalBlurKernel"
        };
        renderPipelines.createComputePipeline(ComputePipelineType::VerticalBlur, verticalBlurConfig);
        
        ComputePipelineConfig horizontalBlurConfig{
            .label = "Vertical Blur",
            .computeFunctionName = "horizontalBlurKernel"
        };
        renderPipelines.createComputePipeline(ComputePipelineType::HorizontalBlur, horizontalBlurConfig);
    }
}

void Engine::createSphereGrid() {
    debug->clearLines();
    
    debugProbeCount = floor(metalLayer.drawableSize.width / (PROBE_SPACING * 1 << debugCascadeLevel)) * floor(metalLayer.drawableSize.height / (PROBE_SPACING * 1 << debugCascadeLevel));
    const float sphereRadius = 0.001f * float(1 << debugCascadeLevel) * PROBE_SPACING;
    simd::float3 sphereColor = {1.0f, 0.0f, 0.0f};
    std::vector<simd::float4> spherePositions;
    
    Probe* probes = reinterpret_cast<Probe*>(probePosBuffer[currentFrameIndex][debugCascadeLevel]->contents());
        
     for (int i = 0; i < debugProbeCount; ++i) {
         spherePositions.push_back(probes[i].position);
     }

    debug->drawSpheres(spherePositions, sphereRadius, sphereColor);
}

void Engine::createDebugLines() {
    
    rayCount = debugProbeCount * BASE_RAY * (1 << (2 * debugCascadeLevel));
    
    std::vector<simd::float4> startPoints;
    std::vector<simd::float4> endPoints;
    std::vector<simd::float4> colors;
    
    ProbeRay* rays = reinterpret_cast<ProbeRay*>(rayBuffer[currentFrameIndex][debugCascadeLevel]->contents());
    
    for (int i = 0; i < rayCount; i++) {
        startPoints.push_back(rays[i].intervalStart);
        endPoints.push_back(rays[i].intervalEnd);
        colors.push_back(rays[i].color);
    }

    debug->drawLines(startPoints, endPoints, colors);
}

void Engine::drawDebug(MTL::RenderCommandEncoder* commandEncoder, MTL::CommandBuffer* commandBuffer) {
    commandEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::ForwardDebug));

    commandEncoder->setVertexBuffer(debug->lineBuffer, 0, 0);
    commandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);

    uint32_t* lineCount = reinterpret_cast<uint32_t*>(debug->lineCountBuffer->contents());
    
    if (lineCount != nil && *lineCount > 0 && editor->debug.enableDebugFeature) {
         commandEncoder->drawPrimitives(MTL::PrimitiveTypeLine, 0, *lineCount * 2, 1);
    }
    editor->endFrame(commandBuffer, commandEncoder);
}

void Engine::dispatchRaytracing(MTL::CommandBuffer* commandBuffer) {
    uint width = metalLayer.drawableSize.width;
    uint height = metalLayer.drawableSize.height;
    
    // Get required textures using enum-based lookup
    MTL::Texture* finalGatherTex = resourceManager->getTexture(TextureName::FinalGatherTexture);
    MTL::Texture* linearDepthTex = resourceManager->getTexture(TextureName::LinearDepthTexture);
    
    // Make sure required textures exist
    if (!finalGatherTex || !linearDepthTex) {
        std::cerr << "Error: Missing textures for ray tracing dispatch" << std::endl;
        return;
    }
    
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
    rcRenderTargets[0] = metalDevice->newTexture(desc);
    rcRenderTargets[0]->setLabel(label);
    
    labelStr = "Render Target" + std::to_string(1);
    label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
    rcRenderTargets[1] = metalDevice->newTexture(desc);
    rcRenderTargets[1]->setLabel(label);
    
    MTL::Texture* lastMergedTexture = nil;
    int pingPongIndex = 0;
    
    for (int level = CASCADE_LEVEL - 1; level >= (editor->debug.debugCascadeLevel == -1 ? 0 : editor->debug.debugCascadeLevel); --level) {
        MTL::ComputeCommandEncoder* computeEncoder = commandBuffer->computeCommandEncoder();
        computeEncoder->setLabel(NS::String::string(("Ray Tracing Cascade " + std::to_string(level)).c_str(), NS::ASCIIStringEncoding));
        
        // Update cascade level in frame data
        CascadeData *cascadeData = reinterpret_cast<CascadeData*>(cascadeDataBuffer[currentFrameIndex][level]->contents());
        cascadeData->cascadeLevel = level;
        cascadeData->probeSpacing = PROBE_SPACING;
        cascadeData->intervalLength = editor->debug.intervalLength;
        cascadeData->maxCascade = CASCADE_LEVEL-1;
        cascadeData->enableSky = editor->debug.sky ? 1.0 : 0.0;
        cascadeData->enableSun = editor->debug.sun ? 1.0 : 0.0;
        
        MTL::Texture* currentRenderTarget = nil;
        
        if (level == CASCADE_LEVEL - 1 && (editor->debug.debugCascadeLevel == -1 ? 0 : editor->debug.debugCascadeLevel) != CASCADE_LEVEL - 1) {
            currentRenderTarget = rcRenderTargets[pingPongIndex];
            pingPongIndex = 1 - pingPongIndex;
            lastMergedTexture = nil;
        } else if (level > (editor->debug.debugCascadeLevel == -1 ? 0 : editor->debug.debugCascadeLevel)) {
            currentRenderTarget = rcRenderTargets[pingPongIndex];
            pingPongIndex = 1 - pingPongIndex;
        } else {
            currentRenderTarget = finalGatherTex;
        }
        
        computeEncoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::Raytracing));
        computeEncoder->setTexture(currentRenderTarget, TextureIndexRadiance);
        
        if (level < CASCADE_LEVEL-1) {
            computeEncoder->setTexture(lastMergedTexture, TextureIndexRadianceUpper);
            computeEncoder->useResource(lastMergedTexture, MTL::ResourceUsageRead);
        }
        
        computeEncoder->setBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
        computeEncoder->setBuffer(cascadeDataBuffer[currentFrameIndex][level], 0, BufferIndexCascadeData);
        
        // Get the resource buffer from RayTracingManager
        MTL::Buffer* resourceBuffer = rayTracingManager->getResourceBuffer();
        computeEncoder->setBuffer(resourceBuffer, 0, BufferIndexResources);
        
        if (createDebugData) {
            computeEncoder->setBuffer(probePosBuffer[currentFrameIndex][level], 0, BufferIndexProbeData);
            computeEncoder->setBuffer(rayBuffer[currentFrameIndex][level], 0, BufferIndexProbeRayData);
        }
        
        computeEncoder->setTexture(linearDepthTex, TextureIndexDepthTexture);

        computeEncoder->useResource(resourceBuffer, MTL::ResourceUsageRead);
        if (createDebugData) {
            computeEncoder->useResource(probePosBuffer[currentFrameIndex][level], MTL::ResourceUsageWrite);
            computeEncoder->useResource(rayBuffer[currentFrameIndex][level], MTL::ResourceUsageWrite);
        }
        computeEncoder->useResource(linearDepthTex, MTL::ResourceUsageRead);
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
        uint raysPerDim =  (1 << (level + 2));
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
    
    desc->release();
    rcRenderTargets[0]->release();
    rcRenderTargets[1]->release();
}

void Engine::dispatchTwoPassBlur(MTL::CommandBuffer* commandBuffer) {
    // Use enum-based texture lookups
    MTL::Texture* finalGatherTex = resourceManager->getTexture(TextureName::FinalGatherTexture);
    MTL::Texture* intermediateTex = resourceManager->getTexture(TextureName::IntermediateBlurTexture);
    MTL::Texture* blurredColorTex = resourceManager->getTexture(TextureName::BlurredColorTexture);
    
    // Make sure textures exist
    if (!finalGatherTex || !intermediateTex || !blurredColorTex) {
        std::cerr << "Error: Missing textures for two-pass blur" << std::endl;
        return;
    }
    
    uint width = finalGatherTex->width();
    uint height = finalGatherTex->height();
    
    MTL::Size threadGroupSize = MTL::Size(16, 16, 1);
    MTL::Size threadgroups = MTL::Size((width + threadGroupSize.width - 1) / threadGroupSize.width,
                                     (height + threadGroupSize.height - 1) / threadGroupSize.height, 1);
    
    // First pass - Horizontal blur
    MTL::ComputeCommandEncoder* horizontalEncoder = commandBuffer->computeCommandEncoder();
    horizontalEncoder->setLabel(NS::String::string("Horizontal Blur", NS::ASCIIStringEncoding));
    horizontalEncoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::HorizontalBlur));
    
    horizontalEncoder->setBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    horizontalEncoder->setTexture(finalGatherTex, TextureIndexRadianceUpper);
    horizontalEncoder->setTexture(intermediateTex, TextureIndexRadiance);
    
    horizontalEncoder->useResource(finalGatherTex, MTL::ResourceUsageRead);
    horizontalEncoder->useResource(intermediateTex, MTL::ResourceUsageWrite);
    
    horizontalEncoder->dispatchThreadgroups(threadgroups, threadGroupSize);
    horizontalEncoder->endEncoding();
    
    // Second pass - Vertical blur
    MTL::ComputeCommandEncoder* verticalEncoder = commandBuffer->computeCommandEncoder();
    verticalEncoder->setLabel(NS::String::string("Vertical Blur", NS::ASCIIStringEncoding));
    verticalEncoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::VerticalBlur));
    
    verticalEncoder->setBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    verticalEncoder->setTexture(intermediateTex, TextureIndexRadianceUpper);
    verticalEncoder->setTexture(blurredColorTex, TextureIndexRadiance);
    
    verticalEncoder->useResource(intermediateTex, MTL::ResourceUsageRead);
    verticalEncoder->useResource(blurredColorTex, MTL::ResourceUsageWrite);
    
    verticalEncoder->dispatchThreadgroups(threadgroups, threadGroupSize);
    verticalEncoder->endEncoding();
}

void Engine::createViewRenderPassDescriptor() {
    // Define GBuffer formats
    albedoSpecularGBufferFormat = MTL::PixelFormatRGBA8Unorm_sRGB;
    normalMapGBufferFormat = MTL::PixelFormatRGBA8Snorm;
    depthGBufferFormat = MTL::PixelFormatR32Float;
    
    uint32_t width = metalLayer.drawableSize.width;
    uint32_t height = metalLayer.drawableSize.height;
    
    // Create GBuffer textures using ResourceManager with enums
    albedoSpecularGBuffer = resourceManager->createGBufferTexture(
        width, height, albedoSpecularGBufferFormat, TextureName::AlbedoGBuffer
    );
    
    normalMapGBuffer = resourceManager->createGBufferTexture(
        width, height, normalMapGBufferFormat, TextureName::NormalGBuffer
    );
    
    depthGBuffer = resourceManager->createGBufferTexture(
        width, height, depthGBufferFormat, TextureName::DepthGBuffer
    );
    
    // Create depth/stencil texture
    depthStencilTexture = resourceManager->createDepthStencilTexture(
        width, height, TextureName::DepthStencilTexture
    );
    
    // Create render pass descriptor
    viewRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    
    // Set up render pass descriptor attachments
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoSpecularGBuffer);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalMapGBuffer);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setTexture(depthGBuffer);
    viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
    viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
    
    // Configure load/store actions
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setLoadAction(MTL::LoadActionClear);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setStoreAction(MTL::StoreActionStore);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setClearColor(MTL::ClearColor(0.0, 0.0, 0.0, 1.0));
    
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setLoadAction(MTL::LoadActionClear);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setStoreAction(MTL::StoreActionStore);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setClearColor(MTL::ClearColor(0.0, 0.0, 0.0, 1.0));
    
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setLoadAction(MTL::LoadActionClear);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setStoreAction(MTL::StoreActionStore);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setClearColor(MTL::ClearColor(1.0, 1.0, 1.0, 1.0));
    
    viewRenderPassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionDontCare);
    viewRenderPassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionDontCare);
    viewRenderPassDescriptor->depthAttachment()->setClearDepth(1.0);
    
    viewRenderPassDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionDontCare);
    viewRenderPassDescriptor->stencilAttachment()->setStoreAction(MTL::StoreActionDontCare);
    viewRenderPassDescriptor->stencilAttachment()->setClearStencil(0);
    
    // Forward Debug
    forwardDepthStencilTexture = resourceManager->createDepthStencilTexture(
        width, height, TextureName::ForwardDepthStencilTexture
    );
    
    forwardDescriptor = MTL::RenderPassDescriptor::alloc()->init();

    // Final Gathering
    finalGatherDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    
    // Create linear depth texture for prepass
    linearDepthTexture = resourceManager->createRenderTargetTexture(
        width, height, MTL::PixelFormatR32Float, TextureName::LinearDepthTexture
    );

    // Create depth prepass descriptor
    depthPrepassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    depthPrepassDescriptor->colorAttachments()->object(0)->setTexture(linearDepthTexture);
    depthPrepassDescriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadActionClear);
    depthPrepassDescriptor->colorAttachments()->object(0)->setStoreAction(MTL::StoreActionStore);
    depthPrepassDescriptor->colorAttachments()->object(0)->setClearColor(MTL::ClearColor(1.0, 1.0, 1.0, 1.0)); // Far depth

    // Set up the depth/stencil attachment for z-buffer
    depthPrepassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
    depthPrepassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionClear);
    depthPrepassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionStore);
    depthPrepassDescriptor->depthAttachment()->setClearDepth(1.0);

    // Also set up the stencil attachment since we're using a combined depth/stencil texture
    depthPrepassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
    depthPrepassDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionClear);
    depthPrepassDescriptor->stencilAttachment()->setStoreAction(MTL::StoreActionStore);
    depthPrepassDescriptor->stencilAttachment()->setClearStencil(0);
    
    // Min Max Depth Buffer
    MTL::TextureDescriptor* minMaxDescriptor = MTL::TextureDescriptor::alloc()->init();
    minMaxDescriptor->setTextureType(MTL::TextureType2D);
    minMaxDescriptor->setPixelFormat(MTL::PixelFormatRG32Float); // 2x32-bit floats
    minMaxDescriptor->setWidth(width);
    minMaxDescriptor->setHeight(height);
    minMaxDescriptor->setStorageMode(MTL::StorageModeShared);
    minMaxDescriptor->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    minMaxDescriptor->setMipmapLevelCount(log2(std::max(metalLayer.drawableSize.width, metalLayer.drawableSize.height)) + 1);
    
    minMaxDepthTexture = resourceManager->createTexture(minMaxDescriptor, TextureName::MinMaxDepthTexture);
    minMaxDescriptor->release();
    
    // Create the raytracing output texture
    finalGatherTexture = resourceManager->createRaytracingOutputTexture(width, height, TextureName::FinalGatherTexture);
    
    // Create blur textures
    blurredColor = resourceManager->createRaytracingOutputTexture(width, height, TextureName::BlurredColorTexture);
    
    // Create intermediate blur texture
    MTL::TextureDescriptor* blurDesc = MTL::TextureDescriptor::alloc()->init();
    blurDesc->setTextureType(MTL::TextureType2D);
    blurDesc->setPixelFormat(MTL::PixelFormatRGBA16Float);
    blurDesc->setWidth(width);
    blurDesc->setHeight(height);
    blurDesc->setStorageMode(MTL::StorageModePrivate);
    blurDesc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    intermediateBlurTexture = resourceManager->createTexture(blurDesc, TextureName::IntermediateBlurTexture);
    blurDesc->release();
}

void Engine::updateRenderPassDescriptor() {
    // Update all render pass descriptor attachments with resized textures
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoSpecularGBuffer);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalMapGBuffer);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setTexture(depthGBuffer);

    // Update depth/stencil attachment
    viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
    viewRenderPassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionClear);
    viewRenderPassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionStore);
    viewRenderPassDescriptor->depthAttachment()->setClearDepth(1.0); // Clear depth to furthest
    viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
    viewRenderPassDescriptor->stencilAttachment()->setClearStencil(0); // Clear stencil
    
    // Set up the final gather descriptor to render to the drawable
    finalGatherDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    finalGatherDescriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadActionClear);
    finalGatherDescriptor->colorAttachments()->object(0)->setStoreAction(MTL::StoreActionStore);
    finalGatherDescriptor->colorAttachments()->object(0)->setClearColor(MTL::ClearColor(0.0, 0.4, 0.8, 1.0));
    
    // Set up the forward descriptor to render on top of final gather results
    forwardDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    forwardDescriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadActionLoad); // Preserve Final Gathering results
    forwardDescriptor->depthAttachment()->setTexture(forwardDepthStencilTexture);
    forwardDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionLoad);
    forwardDescriptor->depthAttachment()->setClearDepth(1.0);
    forwardDescriptor->stencilAttachment()->setTexture(forwardDepthStencilTexture);
    forwardDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionLoad);
    forwardDescriptor->stencilAttachment()->setClearStencil(0);

    // Set up the depth prepass descriptor
    depthPrepassDescriptor->colorAttachments()->object(0)->setTexture(linearDepthTexture);
    depthPrepassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
    depthPrepassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
}

void Engine::renderDepthPrepass(MTL::CommandBuffer* commandBuffer) {
    MTL::Texture* linearDepthTexture = resourceManager->getTexture(TextureName::LinearDepthTexture);
    MTL::Texture* depthStencilTexture = resourceManager->getTexture(TextureName::DepthStencilTexture);
    
    // Make sure we have the necessary textures
    if (!linearDepthTexture || !depthStencilTexture) {
        std::cerr << "Error: Missing textures for depth prepass" << std::endl;
        return;
    }
    
    // Update the descriptor with the latest textures
    depthPrepassDescriptor->colorAttachments()->object(0)->setTexture(linearDepthTexture);
    depthPrepassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
    depthPrepassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
    
    MTL::RenderCommandEncoder* depthPrepassEncoder = commandBuffer->renderCommandEncoder(depthPrepassDescriptor);
    depthPrepassEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    depthPrepassEncoder->setLabel(NS::String::string("Depth Prepass", NS::ASCIIStringEncoding));
    
    depthPrepassEncoder->setCullMode(MTL::CullModeBack);
    depthPrepassEncoder->setDepthStencilState(renderPipelines.getDepthStencilState(DepthStencilType::DepthPrepass));
    depthPrepassEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::DepthPrepass));
    depthPrepassEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    depthPrepassEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    
    // Render all meshes to depth buffer
    for (int i = 0; i < meshes.size(); i++) {
        depthPrepassEncoder->setVertexBuffer(meshes[i]->vertexBuffer, 0, BufferIndexVertexData);
        
        matrix_float4x4 modelMatrix = meshes[i]->getTransformMatrix();
        depthPrepassEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), BufferIndexVertexBytes);
        
        depthPrepassEncoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, meshes[i]->indexCount, MTL::IndexTypeUInt32, meshes[i]->indexBuffer, 0);
    }
    
    depthPrepassEncoder->endEncoding();
}

void Engine::drawMeshes(MTL::RenderCommandEncoder* renderCommandEncoder) {
	renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
    
    for (int i = 0; i < meshes.size(); i++) {
        if (meshes[i]->meshHasTextures()) {
            renderCommandEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::GBufferTextured));
        } else {
            renderCommandEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::GBufferNonTextured));
        }

        //	renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines);
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

void Engine::drawGBuffer(MTL::RenderCommandEncoder* renderCommandEncoder)
{
    MTL::Texture* albedoGBuffer = resourceManager->getTexture(TextureName::AlbedoGBuffer);
    MTL::Texture* normalGBuffer = resourceManager->getTexture(TextureName::NormalGBuffer);
    MTL::Texture* depthGBuffer = resourceManager->getTexture(TextureName::DepthGBuffer);
    MTL::Texture* depthStencilTex = resourceManager->getTexture(TextureName::DepthStencilTexture);
    
    // Make sure the textures exist
    if (!albedoGBuffer || !normalGBuffer || !depthGBuffer || !depthStencilTex) {
        std::cerr << "Error: Missing textures for G-Buffer rendering" << std::endl;
        return;
    }
    
    // Update render pass descriptor with current textures
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoGBuffer);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalGBuffer);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setTexture(depthGBuffer);
    viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTex);
    viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTex);

    renderCommandEncoder->pushDebugGroup(NS::String::string("Draw G-Buffer", NS::ASCIIStringEncoding));
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    renderCommandEncoder->setDepthStencilState(renderPipelines.getDepthStencilState(DepthStencilType::GBuffer));
    renderCommandEncoder->setStencilReferenceValue(128);
    renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);

    drawMeshes(renderCommandEncoder);
    renderCommandEncoder->popDebugGroup();
}

void Engine::drawFinalGathering(MTL::RenderCommandEncoder* renderCommandEncoder)
{
    MTL::Texture* finalGatherTex = resourceManager->getTexture(TextureName::FinalGatherTexture);
    MTL::Texture* normalMapTex = resourceManager->getTexture(TextureName::NormalGBuffer);
    MTL::Texture* albedoSpecularTex = resourceManager->getTexture(TextureName::AlbedoGBuffer);
    MTL::Texture* linearDepthTex = resourceManager->getTexture(TextureName::LinearDepthTexture);
    
    // Check that required textures exist
    if (!finalGatherTex || !normalMapTex || !albedoSpecularTex || !linearDepthTex) {
        std::cerr << "Error: Missing textures for final gathering pass" << std::endl;
        return;
    }
    
    bool doBilinear = editor->debug.debugCascadeLevel == -1;
    bool drawSky = editor->debug.sky;
    renderCommandEncoder->setCullMode(MTL::CullModeNone);

    renderCommandEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::FinalGather));
    renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    
    renderCommandEncoder->setFragmentTexture(finalGatherTex, TextureIndexRadiance);
    renderCommandEncoder->setFragmentTexture(linearDepthTex, TextureIndexDepthTexture);
    renderCommandEncoder->setFragmentTexture(normalMapTex, TextureIndexNormal);
    renderCommandEncoder->setFragmentTexture(albedoSpecularTex, TextureIndexBaseColor);
    renderCommandEncoder->setFragmentBytes(&doBilinear, sizeof(bool), 3);
    renderCommandEncoder->setFragmentBytes(&drawSky, sizeof(bool), 4);

    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, 0, 3, 1);
}

void Engine::dispatchMinMaxDepthMipmaps(MTL::CommandBuffer* commandBuffer) {
    // Use enum-based texture lookups
    MTL::Texture* depthStencilTex = resourceManager->getTexture(TextureName::DepthStencilTexture);
    MTL::Texture* minMaxDepthTex = resourceManager->getTexture(TextureName::MinMaxDepthTexture);
    
    // Make sure textures exist
    if (!depthStencilTex || !minMaxDepthTex) {
        std::cerr << "Error: Missing textures for min/max depth mipmaps" << std::endl;
        return;
    }
    
    MTL::ComputeCommandEncoder* encoder = commandBuffer->computeCommandEncoder();
    {
        encoder->setLabel(NS::String::string("First Min Max Depth", NS::ASCIIStringEncoding));
        encoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::InitMinMaxDepth));

        encoder->setTexture(depthStencilTex, 0);
        encoder->setTexture(minMaxDepthTex, 1);

        MTL::Size threadsPerGroup(8, 8, 1);
        MTL::Size threadgroups((minMaxDepthTex->width() + 7) / 8, (minMaxDepthTex->height() + 7) / 8, 1);

        encoder->dispatchThreadgroups(threadgroups, threadsPerGroup);
    }
    
    encoder->setLabel(NS::String::string("Min Max Depth", NS::ASCIIStringEncoding));
    encoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::MinMaxDepth));

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

void Engine::draw() {
    updateRenderPassDescriptor();
    MTL::CommandBuffer* commandBuffer = beginFrame(false);
    editor->beginFrame(forwardDescriptor);
    camera.position = editor->debug.cameraPosition;

    renderDepthPrepass(commandBuffer);
    
    // G-Buffer pass
    MTL::RenderCommandEncoder* gBufferEncoder = commandBuffer->renderCommandEncoder(viewRenderPassDescriptor);
    gBufferEncoder->setLabel(NS::String::string("GBuffer", NS::ASCIIStringEncoding));
    if (gBufferEncoder) {
        drawGBuffer(gBufferEncoder);
        gBufferEncoder->endEncoding();
    }
    
    dispatchRaytracing(commandBuffer);

    MTL::RenderCommandEncoder* finalGatherEncoder = commandBuffer->renderCommandEncoder(finalGatherDescriptor);
    finalGatherEncoder->setLabel(NS::String::string("Final Gather", NS::ASCIIStringEncoding));
    if (finalGatherEncoder) {
        drawFinalGathering(finalGatherEncoder);
        finalGatherEncoder->endEncoding();
    }

    MTL::RenderCommandEncoder* debugEncoder = commandBuffer->renderCommandEncoder(forwardDescriptor);
    debugEncoder->setLabel(NS::String::string("Debug and ImGui", NS::ASCIIStringEncoding));
    drawDebug(debugEncoder, commandBuffer);
    debugEncoder->endEncoding();

    endFrame(commandBuffer);
}
