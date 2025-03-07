#include "engine.hpp"

Engine::Engine()
: camera(simd::float3{7.0f, 5.0f, 0.0f}, 0.1f, 1000.0f)
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

    editor = std::make_unique<Editor>(glfwWindow, metalDevice);
    debug = std::make_unique<Debug>(metalDevice);

    createCommandQueue();
	loadScene();
    createDefaultLibrary();
    createBuffers();
    renderPipelines.initialize(metalDevice, metalDefaultLibrary);
    defaultVertexDescriptor = createDefaultVertexDescriptor();
    createRenderPipelines();
	createViewRenderPassDescriptor();
    createAccelerationStructureWithDescriptors();
    setupTriangleResources();
}

void Engine::run() {
    while (!glfwWindowShouldClose(glfwWindow)) {
        float currentFrame = glfwGetTime();
        float deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;
        
        camera.processKeyboardInput(glfwWindow, deltaTime);
        
        @autoreleasepool {
            metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
            draw();
        }
        
        glfwPollEvents();
    }
}

void Engine::cleanup() {
    glfwTerminate();
    for (auto& mesh : meshes)
            delete mesh;
	
	for(int frame = 0; frame < MaxFramesInFlight; frame++) {
		frameDataBuffers[frame]->release();
        
        for (int cascade = 0; cascade < cascadeLevel; cascade++) {
            cascadeDataBuffer[frame][cascade]->release();
            probePosBuffer[frame][cascade]->release();
            rayBuffer[frame][cascade]->release();
        }
    }
	
    directionTextures.clear();
    forwardDepthStencilTexture->release();
    rayTracingTexture->release();
    minMaxDepthTexture->release();
    resourceBuffer->release();
	defaultVertexDescriptor->release();
	viewRenderPassDescriptor->release();
    forwardDescriptor->release();
    metalDevice->release();
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
    // Deallocate the textures if they have been created
	if (albedoSpecularGBuffer) {
		albedoSpecularGBuffer->release();
		albedoSpecularGBuffer = nullptr;
	}
	if (normalMapGBuffer) {
		normalMapGBuffer->release();
		normalMapGBuffer = nullptr;
	}
	if (depthGBuffer) {
		depthGBuffer->release();
		depthGBuffer = nullptr;
	}
	if (depthStencilTexture) {
		depthStencilTexture->release();
		depthStencilTexture = nullptr;
	}
    if (rayTracingTexture) {
        rayTracingTexture->release();
        rayTracingTexture = nullptr;
    }
    if (directionTextures.size() > 0) {
        for (auto& texture : directionTextures) {
            texture->release();
            texture = nullptr;
        }
        directionTextures.clear();
    }
    if (forwardDepthStencilTexture) {
        forwardDepthStencilTexture->release();
        forwardDepthStencilTexture = nullptr;
    }
    if (viewRenderPassDescriptor) {
        viewRenderPassDescriptor->release();
        viewRenderPassDescriptor = nullptr;
    }
    if (forwardDescriptor) {
        forwardDescriptor->release();
        forwardDescriptor = nullptr;
    }

	// Recreate G-buffer textures and descriptors
	createViewRenderPassDescriptor();
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
    updateRenderPassDescriptor();
}

void Engine::initWindow() {
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindow = glfwCreateWindow(512, 512, "Metalλαγμένος", NULL, NULL);
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

void Engine::endFrame(MTL::CommandBuffer* commandBuffer, MTL::Drawable* currentDrawable) {
    if(commandBuffer) {
        commandBuffer->presentDrawable(metalDrawable);
        commandBuffer->commit();
        
//        if (frameNumber == 100) {
//            commandBuffer->waitUntilCompleted();
//            createSphereGrid();
//            createDebugLines();
//        }
        
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
    loadSceneFromJSON(std::string(SCENES_PATH) + "/cubeScene.json");
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
        frameDataBuffers[frame] = metalDevice->newBuffer(sizeof(FrameData), MTL::ResourceStorageModeShared);
        frameDataBuffers[frame]->setLabel(NS::String::string("FrameData", NS::ASCIIStringEncoding));
        
        cascadeDataBuffer[frame].resize(cascadeLevel);
        probePosBuffer[frame].resize(cascadeLevel);
        rayBuffer[frame].resize(cascadeLevel);
        for (int cascade = 0; cascade < cascadeLevel; cascade++) {
            std::string labelStr = "Frame: " + std::to_string(frame) + "|CascadeData: " + std::to_string(cascade);
            NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
            cascadeDataBuffer[frame][cascade] = metalDevice->newBuffer(sizeof(CascadeData), MTL::ResourceStorageModeShared);
            cascadeDataBuffer[frame][cascade]->setLabel(label);
            
            debugProbeCount = floor(metalLayer.drawableSize.width / (probeSpacing * 1 << cascade)) * floor(metalLayer.drawableSize.height / (probeSpacing * 1 << cascade));
            size_t probeBufferSize = debugProbeCount * sizeof(Probe);
            rayCount = debugProbeCount * 8 * (1 << (2 * cascade));
            size_t rayBufferSize = rayCount * sizeof(ProbeRay);
            
            labelStr = "Frame: " + std::to_string(frame) + "|CascadeProbes: " + std::to_string(cascade);
            label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
            probePosBuffer[frame][cascade] = metalDevice->newBuffer(probeBufferSize, MTL::ResourceStorageModeShared);
            probePosBuffer[frame][cascade]->setLabel(NS::String::string("probePosBuffer", NS::ASCIIStringEncoding));
            
            labelStr = "Frame: " + std::to_string(frame) + "|CascadeRays: " + std::to_string(cascade);
            label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
            rayBuffer[frame][cascade] = metalDevice->newBuffer(rayBufferSize, MTL::ResourceStorageModeShared);
            rayBuffer[frame][cascade]->setLabel(NS::String::string("rayBuffer", NS::ASCIIStringEncoding));
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
	
	camera.setProjectionMatrix(45, aspectRatio, 0.1f, 100.0f);
	frameData->projection_matrix = camera.getProjectionMatrix();
	frameData->projection_matrix_inverse = matrix_invert(frameData->projection_matrix);
	frameData->view_matrix = camera.getViewMatrix();
    frameData->inverse_view_matrix = camera.getInverseViewMatrix();
    
    frameData->cameraUp         = float4{camera.up.x,       camera.up.y,        camera.up.z, 1.0f};
    frameData->cameraRight      = float4{camera.right.x,    camera.right.y,     camera.right.z, 1.0f};
    frameData->cameraForward    = float4{camera.front.x,    camera.front.y,     camera.front.z, 1.0f};
    frameData->cameraPosition   = float4{camera.position.x, camera.position.y,  camera.position.z, 1.0f};

	// Set screen dimensions
	frameData->framebuffer_width = (uint)metalLayer.drawableSize.width;
	frameData->framebuffer_height = (uint)metalLayer.drawableSize.height;

	// Define the sun color
	frameData->sun_color = simd_make_float4(1.0, 1.0, 1.0, 1.0);
	frameData->sun_specular_intensity = 1.0;

	// Calculate the sun's X position oscillating over time
	float oscillationSpeed = 0.01f;
	float oscillationAmplitude = 12.0f;
	float sunZ = sin(frameNumber * oscillationSpeed) * oscillationAmplitude;

	float sunY = 10.0f;
	float sunX = 0.0f;

	// Sun world position
	float4 sunWorldPosition = {sunX, sunY, /*sunZ*/0.0, 1.0};
	float4 sunWorldDirection = -sunWorldPosition;

	// Update the sun direction in view space
	frameData->sun_eye_direction = sunWorldDirection;

	float4 directionalLightUpVector = {0.0, 1.0, 0.0, 0.0};
	// Update scene matrices
	frameData->scene_model_matrix = matrix4x4_translation(0.0f, 0.0f, 0.0f); // Sponza at origin
	frameData->scene_modelview_matrix = frameData->view_matrix * frameData->scene_model_matrix;
	frameData->scene_normal_matrix = matrix3x3_upper_left(frameData->scene_model_matrix);
    
    frameData->cascadeLevel = cascadeLevel;
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
                {RenderTargetLighting, MTL::PixelFormatBGRA8Unorm},
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
		
		// Setup render state to apply directional light in final pass
		{
            #pragma mark Directional lighting render pipeline setup
            {
                RenderPipelineConfig directionalConfig{
                    .label = "Deferred Directional Lighting",
                    .vertexFunctionName = "deferred_directional_lighting_vertex",
                    .fragmentFunctionName = "deferred_directional_lighting_fragment",
                    .colorPixelFormat = MTL::PixelFormatBGRA8Unorm,
                    .depthPixelFormat = MTL::PixelFormatDepth32Float_Stencil8,
                    .stencilPixelFormat = MTL::PixelFormatDepth32Float_Stencil8,
                    .vertexDescriptor = nullptr
                };

                // Add additional color attachments for GBuffer
                directionalConfig.colorAttachments = {
                    {RenderTargetLighting, MTL::PixelFormatBGRA8Unorm},
                    {RenderTargetAlbedo, albedoSpecularGBufferFormat},
                    {RenderTargetNormal, normalMapGBufferFormat},
                    {RenderTargetDepth, depthGBufferFormat}
                };
                renderPipelines.createRenderPipeline(RenderPipelineType::DirectionalLight, directionalConfig);
            }

			#pragma mark Directional lighting mask depth stencil state setup
			{
				StencilConfig directionalStencil{
                #if LIGHT_STENCIL_CULLING
                    .stencilCompareFunction = MTL::CompareFunctionEqual,
                    .stencilFailureOperation = MTL::StencilOperationKeep,
                    .depthFailureOperation = MTL::StencilOperationKeep,
                    .depthStencilPassOperation = MTL::StencilOperationKeep,
                    .readMask = 0xFF,
                    .writeMask = 0x0
                #endif
                };

                DepthStencilConfig directionalDepthConfig{
                    .label = "Deferred Directional Lighting",
                    .depthCompareFunction = MTL::CompareFunctionAlways,
                    .depthWriteEnabled = false,
                    .frontStencil = directionalStencil,
                    .backStencil = directionalStencil
                };
                renderPipelines.createDepthStencilState(DepthStencilType::DirectionalLight, directionalDepthConfig);
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
}

void Engine::createAccelerationStructureWithDescriptors() {
    // Create a separate command queue for acceleration structure building
    MTL::CommandQueue* commandQueue = metalDevice->newCommandQueue();
    MTL::CommandBuffer* commandBuffer = commandQueue->commandBuffer();

    std::vector<Vertex> mergedVertices;
    std::vector<uint32_t> mergedIndices;

    size_t vertexOffset = 0;
    
    for (const auto& mesh : meshes) {
        matrix_float4x4 modelMatrix = mesh->getTransformMatrix();

        for (const auto& vertex : mesh->vertices) {
            Vertex transformedVertex = vertex;
            transformedVertex.position = modelMatrix * vertex.position;
            mergedVertices.push_back(transformedVertex);
        }

        for (size_t index : mesh->vertexIndices) {
            mergedIndices.push_back(static_cast<uint32_t>(index + vertexOffset));
        }

        vertexOffset += mesh->vertices.size();
        totalTriangles += mesh->triangleCount;
    }

    size_t vertexBufferSize             = mergedVertices.size() * sizeof(Vertex);
    MTL::Buffer* mergedVertexBuffer     = metalDevice->newBuffer(vertexBufferSize, MTL::ResourceStorageModeShared);
    mergedVertexBuffer->setLabel(NS::String::string("mergedVertexBuffer", NS::ASCIIStringEncoding));
    memcpy(mergedVertexBuffer->contents(), mergedVertices.data(), vertexBufferSize);

    size_t indexBufferSize          = mergedIndices.size() * sizeof(uint32_t);
    MTL::Buffer* mergedIndexBuffer  = metalDevice->newBuffer(indexBufferSize, MTL::ResourceStorageModeShared);
    mergedIndexBuffer->setLabel(NS::String::string("mergedIndexBuffer", NS::ASCIIStringEncoding));

    memcpy(mergedIndexBuffer->contents(), mergedIndices.data(), indexBufferSize);

    MTL::AccelerationStructureTriangleGeometryDescriptor* geometryDescriptor = MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();

    geometryDescriptor->setVertexBuffer(mergedVertexBuffer);
    geometryDescriptor->setVertexStride(sizeof(Vertex));
    geometryDescriptor->setVertexFormat(MTL::AttributeFormatFloat3);

    geometryDescriptor->setIndexBuffer(mergedIndexBuffer);
    geometryDescriptor->setIndexType(MTL::IndexTypeUInt32);
    geometryDescriptor->setTriangleCount(static_cast<uint32_t>(totalTriangles));

    NS::Array* geometryDescriptors = NS::Array::array(geometryDescriptor);

    // Set the triangle geometry descriptors in the acceleration structure descriptor
    MTL::PrimitiveAccelerationStructureDescriptor* accelerationStructureDescriptor = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
    accelerationStructureDescriptor->setGeometryDescriptors(geometryDescriptors);

    // Get acceleration structure sizes
    MTL::AccelerationStructureSizes sizes = metalDevice->accelerationStructureSizes(accelerationStructureDescriptor);

    // Create the acceleration structure
    MTL::AccelerationStructure* accelerationStructure = metalDevice->newAccelerationStructure(sizes.accelerationStructureSize);

    // Create a scratch buffer for building the acceleration structure
    MTL::Buffer* scratchBuffer = metalDevice->newBuffer(sizes.buildScratchBufferSize, MTL::ResourceStorageModePrivate);
    scratchBuffer->setLabel(NS::String::string("scratchBuffer", NS::ASCIIStringEncoding));


    // Build the acceleration structure
    MTL::AccelerationStructureCommandEncoder* commandEncoder = commandBuffer->accelerationStructureCommandEncoder();
    commandEncoder->buildAccelerationStructure(accelerationStructure, accelerationStructureDescriptor, scratchBuffer, 0);
    commandEncoder->endEncoding();

    // Commit and wait for the command buffer to complete
    commandBuffer->commit();
    commandBuffer->waitUntilCompleted();

    // Store the acceleration structure for later use
    primitiveAccelerationStructures.push_back(accelerationStructure);

    geometryDescriptor->release();
    geometryDescriptors->release();
    accelerationStructureDescriptor->release();
    scratchBuffer->release();
    commandBuffer->release();
    commandQueue->release();
}

void Engine::setupTriangleResources() {
    size_t resourceStride = sizeof(TriangleData);
    size_t bufferLength = resourceStride * totalTriangles;

    resourceBuffer = metalDevice->newBuffer(bufferLength, MTL::ResourceStorageModeShared);
    resourceBuffer->setLabel(NS::String::string("Resource Buffer", NS::ASCIIStringEncoding));

    TriangleData* resourceBufferContents = (TriangleData*)((uint8_t*)(resourceBuffer->contents()));
    size_t triangleIndex = 0;

    for (int m = 0; m < meshes.size(); m++) {
        simd::float4 meshColor;
        
        if (meshes[m]->meshInfo.isEmissive) {
            meshColor = simd::float4{
                meshes[m]->meshInfo.emissiveColor.x,
                meshes[m]->meshInfo.emissiveColor.y,
                meshes[m]->meshInfo.emissiveColor.z,
                -1.0f  // Emissive
            };
        } else {
            meshColor = simd::float4{
                meshes[m]->meshInfo.color.x,
                meshes[m]->meshInfo.color.y,
                meshes[m]->meshInfo.color.z,
                1.0f  // Non-emissive
            };
        }
        

        for (size_t i = 0; i < meshes[m]->vertexIndices.size(); i += 3) {
            TriangleData& triangle = resourceBufferContents[triangleIndex++];

            for (size_t j = 0; j < 3; ++j) {
                size_t vertexIndex = meshes[m]->vertexIndices[i + j];
                triangle.normals[j] = meshes[m]->vertices[vertexIndex].normal;
                triangle.colors[j] = meshColor;
            }
        }
    }
}

void Engine::createSphereGrid() {
    int debugCascadeLevel = 0;
    debugProbeCount = floor(metalLayer.drawableSize.width / (probeSpacing * 1 << debugCascadeLevel)) * floor(metalLayer.drawableSize.height / (probeSpacing * 1 << debugCascadeLevel));
    
    const float sphereRadius = 0.006f * float(1 << debugCascadeLevel) * probeSpacing;
    simd::float3 sphereColor = {1.0f, 0.0f, 0.0f};
    std::vector<simd::float4> spherePositions;
    
    Probe* probes = reinterpret_cast<Probe*>(probePosBuffer[currentFrameIndex][debugCascadeLevel]->contents());
        
     for (int i = 0; i < debugProbeCount; ++i) {
         spherePositions.push_back(probes[i].position);
//         std::cout << "Probe: " << i << "\tx: " << probes[i].position.x << "\ty: " << probes[i].position.y << "\tz: " << probes[i].position.z << "\tw: " << probes[i].position.w << "\n";
     }

    debug->drawSpheres(spherePositions, sphereRadius, sphereColor);
}

void Engine::createDebugLines() {
    int debugRayLevel = 0;
    rayCount = debugProbeCount * 8 * (1 << (2 * debugRayLevel));
    
    std::vector<simd::float4> startPoints;
    std::vector<simd::float4> endPoints;
    std::vector<simd::float4> colors;
    
    ProbeRay* rays = reinterpret_cast<ProbeRay*>(rayBuffer[currentFrameIndex][debugRayLevel]->contents());
    
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

    for (int level = cascadeLevel-1; level >= 0; --level) {
        MTL::ComputeCommandEncoder* computeEncoder = commandBuffer->computeCommandEncoder();
        computeEncoder->setLabel(NS::String::string(("Ray Tracing Cascade " + std::to_string(level)).c_str(), NS::ASCIIStringEncoding));
        
        // Update cascade level in frame data
        CascadeData *cascadeData = reinterpret_cast<CascadeData*>(cascadeDataBuffer[currentFrameIndex][level]->contents());
        cascadeData->cascadeLevel = level;
        cascadeData->probeSpacing = probeSpacing;

        computeEncoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::Raytracing));
        computeEncoder->setTexture(directionTextures[level], TextureIndexRadiance);
        
        if (level < cascadeLevel-1) {
            computeEncoder->setTexture(directionTextures[level+1], TextureIndexRadianceUpper);
            computeEncoder->useResource(directionTextures[level + 1], MTL::ResourceUsageRead);
        }
        
        computeEncoder->setBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
        computeEncoder->setBuffer(cascadeDataBuffer[currentFrameIndex][level], 0, BufferIndexCascadeData);
        computeEncoder->setBuffer(resourceBuffer, 0, BufferIndexResources);
        computeEncoder->setBuffer(probePosBuffer[currentFrameIndex][level], 0, BufferIndexProbeData);
        computeEncoder->setBuffer(rayBuffer[currentFrameIndex][level], 0, BufferIndexProbeRayData);
        computeEncoder->setTexture(minMaxDepthTexture, TextureIndexMinMaxDepth);

        computeEncoder->useResource(resourceBuffer, MTL::ResourceUsageRead);
        computeEncoder->useResource(probePosBuffer[currentFrameIndex][level], MTL::ResourceUsageWrite);
        computeEncoder->useResource(rayBuffer[currentFrameIndex][level], MTL::ResourceUsageWrite);
        computeEncoder->useResource(minMaxDepthTexture, MTL::ResourceUsageRead);
        computeEncoder->useResource(directionTextures[level], MTL::ResourceUsageWrite);

        // Set acceleration structures
        for (uint i = 0; i < primitiveAccelerationStructures.size(); i++) {
            computeEncoder->setAccelerationStructure(primitiveAccelerationStructures[i], BufferIndexAccelerationStructure);
            computeEncoder->useResource(primitiveAccelerationStructures[i], MTL::ResourceUsageRead);
        }

        // Compute probe grid and thread counts
        int tile_size = probeSpacing * (1 << level);
        size_t probeGridSizeX = (metalDrawable->texture()->width() + tile_size - 1) / tile_size;
        size_t probeGridSizeY = (metalDrawable->texture()->height() + tile_size - 1) / tile_size;
        size_t numRays = 8 * (1 << (2 * level));
        size_t totalProbes = probeGridSizeX * probeGridSizeY;
        size_t totalThreads = totalProbes * numRays;

        MTL::Size threadGroupSize = MTL::Size(128, 1, 1);
        size_t numThreadGroups = (totalThreads + threadGroupSize.width - 1) / threadGroupSize.width;
        MTL::Size gridSize = MTL::Size(numThreadGroups * threadGroupSize.width, 1, 1);

        computeEncoder->dispatchThreadgroups(MTL::Size(numThreadGroups, 1, 1), threadGroupSize);
        computeEncoder->endEncoding();
    }
}

void Engine::createViewRenderPassDescriptor() {
	MTL::TextureDescriptor* gbufferTextureDesc = MTL::TextureDescriptor::alloc()->init();

	gbufferTextureDesc->setPixelFormat(MTL::PixelFormatRGBA8Unorm_sRGB);
	gbufferTextureDesc->setWidth(metalLayer.drawableSize.width);
	gbufferTextureDesc->setHeight(metalLayer.drawableSize.height);
	gbufferTextureDesc->setMipmapLevelCount(1);
	gbufferTextureDesc->setTextureType(MTL::TextureType2D);

	// StorageModeMemoryLess
	gbufferTextureDesc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
	gbufferTextureDesc->setStorageMode(MTL::StorageModeMemoryless);
	gbufferTextureDesc->setPixelFormat(albedoSpecularGBufferFormat);
	albedoSpecularGBuffer = metalDevice->newTexture(gbufferTextureDesc);
	gbufferTextureDesc->setPixelFormat(normalMapGBufferFormat);
	normalMapGBuffer = metalDevice->newTexture(gbufferTextureDesc);
	gbufferTextureDesc->setPixelFormat(depthGBufferFormat);
	depthGBuffer = metalDevice->newTexture(gbufferTextureDesc);

    // Create depth/stencil texture
    gbufferTextureDesc->setStorageMode(MTL::StorageModeShared); // shared for min max depth buffer
	gbufferTextureDesc->setPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
	depthStencilTexture = metalDevice->newTexture(gbufferTextureDesc);
	
	albedoSpecularGBuffer->setLabel(NS::String::string("Albedo GBuffer", NS::ASCIIStringEncoding));
	normalMapGBuffer->setLabel(NS::String::string("Normal + Specular GBuffer", NS::ASCIIStringEncoding));
	depthGBuffer->setLabel(NS::String::string("Depth GBuffer", NS::ASCIIStringEncoding));
	depthStencilTexture->setLabel(NS::String::string("Depth-Stencil Texture", NS::ASCIIStringEncoding));

	gbufferTextureDesc->release();
	
	viewRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

	// Set up render pass descriptor attachments
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoSpecularGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalMapGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setTexture(depthGBuffer);
	viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
	viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
	
	// Configure load/store actions
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setLoadAction(MTL::LoadActionDontCare);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setStoreAction(MTL::StoreActionDontCare);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setClearColor(MTL::ClearColor(0.0, 0.0, 0.0, 1.0));
	
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setLoadAction(MTL::LoadActionDontCare);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setStoreAction(MTL::StoreActionDontCare);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setClearColor(MTL::ClearColor(0.0, 0.0, 0.0, 1.0));
	
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setLoadAction(MTL::LoadActionDontCare);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setStoreAction(MTL::StoreActionDontCare);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setClearColor(MTL::ClearColor(1.0, 1.0, 1.0, 1.0));
	
	viewRenderPassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionDontCare);
	viewRenderPassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionDontCare);
	viewRenderPassDescriptor->depthAttachment()->setClearDepth(1.0);
	
	viewRenderPassDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionDontCare);
	viewRenderPassDescriptor->stencilAttachment()->setStoreAction(MTL::StoreActionDontCare);
	viewRenderPassDescriptor->stencilAttachment()->setClearStencil(0);
    
    // Ray tracing texture
    MTL::TextureDescriptor* raytracingTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    raytracingTextureDescriptor->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    raytracingTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    raytracingTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    raytracingTextureDescriptor->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    raytracingTextureDescriptor->setSampleCount(1);

    rayTracingTexture = metalDevice->newTexture(raytracingTextureDescriptor);

    raytracingTextureDescriptor->release();
    
    // Forward Debug
    MTL::TextureDescriptor* depthStencilDesc = MTL::TextureDescriptor::alloc()->init();
    depthStencilDesc->setTextureType(MTL::TextureType2D);
    depthStencilDesc->setPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
    depthStencilDesc->setWidth(metalLayer.drawableSize.width);
    depthStencilDesc->setHeight(metalLayer.drawableSize.height);
    depthStencilDesc->setStorageMode(MTL::StorageModePrivate);
    depthStencilDesc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

    forwardDepthStencilTexture = metalDevice->newTexture(depthStencilDesc);
    depthStencilDesc->release();
    
    forwardDescriptor = MTL::RenderPassDescriptor::alloc()->init();

    // Min Max Depth Buffer
    MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
    descriptor->setTextureType(MTL::TextureType2D);
    descriptor->setPixelFormat(MTL::PixelFormatRG32Float); // 2x32-bit floats
    descriptor->setWidth(metalLayer.drawableSize.width);
    descriptor->setHeight(metalLayer.drawableSize.height);
    descriptor->setStorageMode(MTL::StorageModeShared);
    descriptor->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    descriptor->setMipmapLevelCount(log2(std::max(metalLayer.drawableSize.width, metalLayer.drawableSize.height)));

    minMaxDepthTexture = metalDevice->newTexture(descriptor);
    descriptor->release();

    // Direction Texture
    directionTextures.resize(cascadeLevel);

    for (int cascade = 0; cascade < cascadeLevel; ++cascade) {
        int tileSize = probeSpacing * (1 << cascade);
        unsigned long probeGridSizeX = (metalLayer.drawableSize.width + tileSize - 1) / tileSize;
        unsigned long probeGridSizeY = (metalLayer.drawableSize.height + tileSize - 1) / tileSize;

        MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
        desc->setTextureType(MTL::TextureType2D);
        desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
        desc->setWidth(probeGridSizeX * tileSize);
        desc->setHeight(probeGridSizeY * tileSize);
        desc->setStorageMode(MTL::StorageModeShared);
        desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);

        std::string labelStr = "RadianceCascade" + std::to_string(cascade);
        NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
        directionTextures[cascade] = metalDevice->newTexture(desc);
        directionTextures[cascade]->setLabel(label);

        desc->release();
    }
}

void Engine::updateRenderPassDescriptor() {
	// Update all render pass descriptor attachments with resized textures
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoSpecularGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalMapGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setTexture(depthGBuffer);

	// Update depth/stencil attachment
	viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
	viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);

    forwardDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture()); 
    forwardDescriptor->depthAttachment()->setTexture(forwardDepthStencilTexture);
    forwardDescriptor->stencilAttachment()->setTexture(forwardDepthStencilTexture);
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
        renderCommandEncoder->setFragmentTexture(meshes[i]->normalTextures, TextureIndexNormal);
        renderCommandEncoder->setFragmentBuffer(meshes[i]->diffuseTextureInfos, 0, BufferIndexDiffuseInfo);
        renderCommandEncoder->setFragmentBuffer(meshes[i]->normalTextureInfos, 0, BufferIndexNormalInfo);
        
        MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
        renderCommandEncoder->drawIndexedPrimitives(typeTriangle, meshes[i]->indexCount, MTL::IndexTypeUInt32, meshes[i]->indexBuffer, 0);
    }
}

void Engine::drawGBuffer(MTL::RenderCommandEncoder* renderCommandEncoder)
{
	renderCommandEncoder->pushDebugGroup(NS::String::string("Draw G-Buffer", NS::ASCIIStringEncoding));
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
//	renderCommandEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::GBuffer));
	renderCommandEncoder->setDepthStencilState(renderPipelines.getDepthStencilState(DepthStencilType::GBuffer));
	renderCommandEncoder->setStencilReferenceValue(128);
    renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
	renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);

	drawMeshes(renderCommandEncoder);
	renderCommandEncoder->popDebugGroup();
}

/// Draw the directional ("sun") light in deferred pass.  Use stencil buffer to limit execution
/// of the shader to only those pixels that should be lit
void Engine::drawDirectionalLight(MTL::RenderCommandEncoder* renderCommandEncoder)
{
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
	renderCommandEncoder->setStencilReferenceValue(128);

	renderCommandEncoder->setRenderPipelineState(renderPipelines.getRenderPipeline(RenderPipelineType::DirectionalLight));
	renderCommandEncoder->setDepthStencilState(renderPipelines.getDepthStencilState(DepthStencilType::DirectionalLight));
	renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
	renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);

	renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)3);
}

void Engine::dispatchMinMaxDepthMipmaps(MTL::CommandBuffer* commandBuffer) {
    {
        MTL::ComputeCommandEncoder* initEncoder = commandBuffer->computeCommandEncoder();
        initEncoder->setLabel(NS::String::string("First Min Max Depth", NS::ASCIIStringEncoding));
        initEncoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::InitMinMaxDepth));

        initEncoder->setTexture(depthStencilTexture, 0);
        initEncoder->setTexture(minMaxDepthTexture, 1);

        MTL::Size threadsPerGroup(8, 8, 1);
        MTL::Size threadgroups((minMaxDepthTexture->width() + 7) / 8, (minMaxDepthTexture->height() + 7) / 8, 1);

        initEncoder->dispatchThreadgroups(threadgroups, threadsPerGroup);
        initEncoder->endEncoding();
    }
    
    MTL::ComputeCommandEncoder* encoder = commandBuffer->computeCommandEncoder();
    encoder->setLabel(NS::String::string("Min Max Depth", NS::ASCIIStringEncoding));
    encoder->setComputePipelineState(renderPipelines.getComputePipeline(ComputePipelineType::MinMaxDepth));

    unsigned long mipLevels = minMaxDepthTexture->mipmapLevelCount();

    for (uint32_t level = 1; level < mipLevels; ++level) {
        std::string labelStr = "MipLevel: " + std::to_string(level);
        NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
        
        encoder->pushDebugGroup(label);
                   
        NS::Range levelRangeSrc(level - 1, 1);
        NS::Range levelRangeDst(level, 1);
        NS::Range sliceRange(0, 1);

        MTL::Texture* srcMip = minMaxDepthTexture->newTextureView(
            MTL::PixelFormatRG32Float,
            MTL::TextureType2D,
            levelRangeSrc,
            sliceRange
        );

        MTL::Texture* dstMip = minMaxDepthTexture->newTextureView(
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
    // First command buffer for raytracing pass
    MTL::CommandBuffer* commandBuffer = beginFrame(false);
    
    // G-Buffer render pass descriptor setup
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetLighting)->setTexture(metalDrawable->texture());
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetLighting)->setLoadAction(MTL::LoadActionClear);
    viewRenderPassDescriptor->colorAttachments()->object(RenderTargetLighting)->setClearColor(MTL::ClearColor(41.0f / 255.0f, 42.0f / 255.0f, 48.0f / 255.0f, 1.0));

    viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
    viewRenderPassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionClear);
    viewRenderPassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionStore);
    viewRenderPassDescriptor->depthAttachment()->setClearDepth(1.0); // Clear depth to farthest
    viewRenderPassDescriptor->stencilAttachment()->setClearStencil(0); // Clear stencil

    // G-Buffer pass
    MTL::RenderCommandEncoder* gBufferEncoder = commandBuffer->renderCommandEncoder(viewRenderPassDescriptor);
    gBufferEncoder->setLabel(NS::String::string("GBuffer", NS::ASCIIStringEncoding));
    if (gBufferEncoder) {
        drawGBuffer(gBufferEncoder);
        drawDirectionalLight(gBufferEncoder);

        gBufferEncoder->endEncoding();
    }

    dispatchMinMaxDepthMipmaps(commandBuffer);
    dispatchRaytracing(commandBuffer);

    // Forward/debug render pass descriptor setup
    forwardDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    forwardDescriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadActionLoad); // Preserve G-Buffer results
    forwardDescriptor->colorAttachments()->object(0)->setClearColor(MTL::ClearColor(41.0f / 255.0f, 42.0f / 255.0f, 48.0f / 255.0f, 1.0));

    forwardDescriptor->depthAttachment()->setTexture(forwardDepthStencilTexture);
    forwardDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionLoad);
    forwardDescriptor->depthAttachment()->setClearDepth(1.0);
    forwardDescriptor->stencilAttachment()->setTexture(forwardDepthStencilTexture);
    forwardDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionLoad);
    forwardDescriptor->stencilAttachment()->setClearStencil(0);
    
    editor->beginFrame(forwardDescriptor);

    MTL::RenderCommandEncoder* debugEncoder = commandBuffer->renderCommandEncoder(forwardDescriptor);
    debugEncoder->setLabel(NS::String::string("Debug and ImGui", NS::ASCIIStringEncoding));
    drawDebug(debugEncoder, commandBuffer);
    debugEncoder->endEncoding();

    endFrame(commandBuffer, metalDrawable);
}
