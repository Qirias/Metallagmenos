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

    createCommandQueue();
	loadScene();
    createDefaultLibrary();
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
	
	for(uint8_t i = 0; i < MaxFramesInFlight; i++) {
		frameDataBuffers[i]->release();
    }
	
    rayTracingTexture->release();
    resourceBuffer->release();
	defaultVertexDescriptor->release();
	shadowMap->release();
	shadowRenderPassDescriptor->release();
	viewRenderPassDescriptor->release();
    shadowPipelineState->release();
	GBufferPipelineState->release();
	directionalLightPipelineState->release();
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
	if (normalShadowGBuffer) {
		normalShadowGBuffer->release();
		normalShadowGBuffer = nullptr;
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
    
	// Recreate G-buffer textures and descriptors
	createViewRenderPassDescriptor();
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
    updateRenderPassDescriptor();
}

void Engine::initWindow() {
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindow = glfwCreateWindow(800, 600, "Metalλαγμένος", NULL, NULL);
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

    // Create a new command buffer for each render pass to the current drawable
    MTL::CommandBuffer* commandBuffer = metalCommandQueue->commandBuffer();

    updateWorldState(isPaused);
	
	return commandBuffer;
}

/// Perform operations necessary to obtain a command buffer for rendering to the drawable. By
/// endoding commands that are not dependant on the drawable in a separate command buffer, Metal
/// can begin executing encoded commands for the frame (commands from the previous command buffer)
/// before a drawable for this frame becomes available.
MTL::CommandBuffer* Engine::beginDrawableCommands() {
	MTL::CommandBuffer* commandBuffer = metalCommandQueue->commandBuffer();
	
	MTL::CommandBufferHandler handler = [this](MTL::CommandBuffer*) {
		// Signal the semaphore for this frame when GPU work is complete
		dispatch_semaphore_signal(frameSemaphores[currentFrameIndex]);
	};
	commandBuffer->addCompletedHandler(handler);
	
	return commandBuffer;
}

void Engine::endFrame(MTL::CommandBuffer* commandBuffer, MTL::Drawable* currentDrawable) {
    if(commandBuffer) {
        commandBuffer->presentDrawable(metalDrawable);
        commandBuffer->commit();
        
        // Move to next frame
        currentFrameIndex = (currentFrameIndex + 1) % MaxFramesInFlight;
    }
}

void Engine::loadScene() {
	defaultVertexDescriptor = MTL::VertexDescriptor::alloc()->init();
	
    std::string objPath = std::string(SCENES_PATH) + "/sponza/sponza.obj";
    meshes.push_back(new Mesh(objPath.c_str(), metalDevice, defaultVertexDescriptor, true));
	
//	GLTFLoader gltfLoader(metalDevice);
//	std::string modelPath = std::string(SCENES_PATH) + "/DamagedHelmet/DamagedHelmet.gltf";
//	auto gltfModel = gltfLoader.loadModel(modelPath);
	
//	// Create mesh from the loaded data
//	mesh = new Mesh(metalDevice,
//				  gltfModel.vertices.data(),
//				  gltfModel.vertices.size(),
//				  gltfModel.indices.data(),
//				  gltfModel.indices.size());
}

void Engine::createDefaultLibrary() {
    // Create an NSString from the metallib path
    NS::String* libraryPath = NS::String::string(
        SHADER_METALLIB,
        NS::UTF8StringEncoding
    );
    
    NS::Error* error = nullptr;

    printf("Selected Device: %s\n", metalDevice->name()->utf8String());

    for(uint8_t i = 0; i < MaxFramesInFlight; i++) {
        frameDataBuffers[i] = metalDevice->newBuffer(sizeof(FrameData), MTL::ResourceStorageModeShared);
        frameDataBuffers[i]->setLabel(NS::String::string("FrameData", NS::ASCIIStringEncoding));
    }
    
    metalDefaultLibrary = metalDevice->newLibrary(libraryPath, &error);
    
    if (!metalDefaultLibrary) {
        std::cerr << "Failed to load metal library at path: " << SHADER_METALLIB;
        if (error) {
            std::cerr << "\nError: " << error->localizedDescription()->utf8String();
        }
        std::exit(-1);
    }
}

void Engine::updateWorldState(bool isPaused) {
	if (!isPaused) {
		frameNumber++;
	}

	FrameData *frameData = (FrameData *)(frameDataBuffers[currentFrameIndex]->contents());

	float aspectRatio = metalDrawable->layer()->drawableSize().width / metalDrawable->layer()->drawableSize().height;
	
	camera.setProjectionMatrix(45, aspectRatio, 0.1f, 1000.0f);
	frameData->projection_matrix = camera.getProjectionMatrix();
	frameData->projection_matrix_inverse = matrix_invert(frameData->projection_matrix);
	frameData->view_matrix = camera.getViewMatrix();
    
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
	float oscillationSpeed = 0.002f;
	float oscillationAmplitude = 4.0f;
	float sunZ = sin(frameNumber * oscillationSpeed) * oscillationAmplitude;

	float sunY = 10.0f;
	float sunX = 0.0f;

	// Sun world position
	float4 sunWorldPosition = {sunX, sunY, sunZ, 1.0};
	float4 sunWorldDirection = -sunWorldPosition;

	// Update the sun direction in view space
	frameData->sun_eye_direction = sunWorldDirection;

	// Compute shadow view matrix for sun
	float4 directionalLightUpVector = {0.0, 1.0, 0.0, 0.0};
	float4x4 shadowViewMatrix = matrix_look_at_right_hand(sunWorldPosition.xyz,
															(float3){0, 0, 0}, // Sponza at origin
															directionalLightUpVector.xyz);

	// Update scene and shadow matrices
	frameData->scene_model_matrix = matrix4x4_translation(0.0f, 0.0f, 0.0f); // Sponza at origin
	frameData->scene_modelview_matrix = frameData->view_matrix * frameData->scene_model_matrix;
	frameData->scene_normal_matrix = matrix3x3_upper_left(frameData->scene_model_matrix);
	frameData->shadow_mvp_matrix = shadowProjectionMatrix * shadowViewMatrix * frameData->scene_model_matrix;

	// Calculate shadow map transform
	float4x4 shadowScale = matrix4x4_scale(0.5f, -0.5f, 1.0f);
	float4x4 shadowTranslate = matrix4x4_translation(0.5f, 0.5f, 0.0f);
	float4x4 shadowTransform = shadowTranslate * shadowScale;

	frameData->shadow_mvp_xform_matrix = shadowTransform * frameData->shadow_mvp_matrix;
	
	  
	// Calculate cascade splits
	float cascade_splits[SHADOW_CASCADE_COUNT];
	calculateCascadeSplits(0.1f, 400.0f, cascade_splits);
	
	simd::float3 frustumCorners[8];
	
	float prevSplitDist = 0.1f;
	for (int i = 0; i < SHADOW_CASCADE_COUNT; i++) {
		camera.setFrustumCornersWorldSpace(frustumCorners, prevSplitDist, cascade_splits[i]);
		
		for (int j = 0; j < 4; j++) {
			simd::float3 dist = frustumCorners[j + 4] - frustumCorners[j]; // Direction vector
			
			// Move frustum corners closer of further. Based on the cascade split
			// Can be closer because we are doing logarithmic split
			frustumCorners[j + 4] = frustumCorners[j] + dist * cascade_splits[i];
			// Near corners adjusted based on the previous cascades far split
			frustumCorners[j] = frustumCorners[j] + dist * prevSplitDist;
		}

		// Calculate optimal projection matrix for this cascade
		shadowCascadeProjectionMatrices[i] = calculateCascadeProjectionMatrix(frustumCorners, prevSplitDist, cascade_splits[i]);

		// Update frame data with cascade information
		frameData->shadow_cascade_mvp_matrices[i] = shadowCascadeProjectionMatrices[i] * shadowViewMatrix * frameData->scene_model_matrix;
		frameData->shadow_cascade_mvp_xform_matrices[i] = shadowTransform * frameData->shadow_cascade_mvp_matrices[i];

		prevSplitDist = cascade_splits[i];
	}
}


void Engine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void Engine::createRenderPipelines() {
    NS::Error* error;
	
	albedoSpecularGBufferFormat = MTL::PixelFormatRGBA8Unorm_sRGB;
	normalShadowGBufferFormat 	= MTL::PixelFormatRGBA8Snorm;
	depthGBufferFormat			= MTL::PixelFormatR32Float;

    #pragma mark Deferred render pipeline setup
    {
		{
			MTL::Function* GBufferVertexFunction = metalDefaultLibrary->newFunction(NS::String::string("gbuffer_vertex", NS::ASCIIStringEncoding));
			MTL::Function* GBufferFragmentFunction = metalDefaultLibrary->newFunction(NS::String::string("gbuffer_fragment", NS::ASCIIStringEncoding));

			assert(GBufferVertexFunction && "Failed to load gbuffer_vertex shader");
			assert(GBufferFragmentFunction && "Failed to load gbuffer_fragment shader");

			MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();

			renderPipelineDescriptor->setLabel(NS::String::string("G-buffer Creation", NS::ASCIIStringEncoding));
			renderPipelineDescriptor->setVertexDescriptor(defaultVertexDescriptor);

			// MTL::PixelFormatInvalid if not single pass deferred rendering
			renderPipelineDescriptor->colorAttachments()->object(RenderTargetLighting)->setPixelFormat(MTL::PixelFormat::PixelFormatBGRA8Unorm);

			renderPipelineDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setPixelFormat(albedoSpecularGBufferFormat);
			renderPipelineDescriptor->colorAttachments()->object(RenderTargetNormal)->setPixelFormat(normalShadowGBufferFormat);
			renderPipelineDescriptor->colorAttachments()->object(RenderTargetDepth)->setPixelFormat(depthGBufferFormat);
			renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormat::PixelFormatDepth32Float_Stencil8);
			renderPipelineDescriptor->setStencilAttachmentPixelFormat(MTL::PixelFormat::PixelFormatDepth32Float_Stencil8);

			renderPipelineDescriptor->setVertexFunction(GBufferVertexFunction);
			renderPipelineDescriptor->setFragmentFunction(GBufferFragmentFunction);

			GBufferPipelineState = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

			assert(error == nil && "Failed to create GBuffer render pipeline state");
			
			renderPipelineDescriptor->release();
			GBufferVertexFunction->release();
			GBufferFragmentFunction->release();
		}
		
		#pragma mark GBuffer depth state setup
		{
		#if LIGHT_STENCIL_CULLING
			MTL::StencilDescriptor* stencilStateDesc = MTL::StencilDescriptor::alloc()->init();
			stencilStateDesc->setStencilCompareFunction(MTL::CompareFunctionAlways);
			stencilStateDesc->setStencilFailureOperation(MTL::StencilOperationKeep);
			stencilStateDesc->setDepthFailureOperation(MTL::StencilOperationKeep);
			stencilStateDesc->setDepthStencilPassOperation(MTL::StencilOperationReplace);
			stencilStateDesc->setReadMask(0x0);
			stencilStateDesc->setWriteMask(0xFF);
		#else
			MTL::StencilDescriptor* stencilStateDesc = MTL::StencilDescriptor::alloc()->init();
		#endif
			MTL::DepthStencilDescriptor* depthStencilDesc = MTL::DepthStencilDescriptor::alloc()->init();
			depthStencilDesc->setLabel(NS::String::string("G-buffer Creation", NS::ASCIIStringEncoding));
			depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionLess);
			depthStencilDesc->setDepthWriteEnabled(true);
			depthStencilDesc->setFrontFaceStencil(stencilStateDesc);
			depthStencilDesc->setBackFaceStencil(stencilStateDesc);

			GBufferDepthStencilState = metalDevice->newDepthStencilState(depthStencilDesc);
			depthStencilDesc->release();
			stencilStateDesc->release();
		}
		
		// Setup render state to apply directional light and shadow in final pass
		{
			#pragma mark Directional lighting render pipeline setup
			{
				MTL::Function* directionalVertexFunction = metalDefaultLibrary->newFunction(NS::String::string("deferred_directional_lighting_vertex", NS::ASCIIStringEncoding));
				assert(directionalVertexFunction && "Failed to load deferred_directional_lighting_vertex");
				MTL::Function* directionalFragmentFunction = metalDefaultLibrary->newFunction(NS::String::string("deferred_directional_lighting_fragment", NS::ASCIIStringEncoding));
				assert(directionalFragmentFunction && "Failed to load deferred_directional_lighting_fragment");
				
				MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
				
				renderPipelineDescriptor->setLabel(NS::String::string("Deferred Directional Lighting", NS::ASCIIStringEncoding));
				renderPipelineDescriptor->setVertexDescriptor(nullptr);
				renderPipelineDescriptor->setVertexFunction(directionalVertexFunction);
				renderPipelineDescriptor->setFragmentFunction(directionalFragmentFunction);
				renderPipelineDescriptor->colorAttachments()->object(RenderTargetLighting)->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
			
				// Single Pass Deferred Rendering
				renderPipelineDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setPixelFormat(albedoSpecularGBufferFormat);
				renderPipelineDescriptor->colorAttachments()->object(RenderTargetNormal)->setPixelFormat(normalShadowGBufferFormat);
				renderPipelineDescriptor->colorAttachments()->object(RenderTargetDepth)->setPixelFormat(depthGBufferFormat);
				
				renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
				renderPipelineDescriptor->setStencilAttachmentPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
				
				directionalLightPipelineState = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
				
				assert(error == nil && "Failed to create directional light render pipeline state");
				
				renderPipelineDescriptor->release();
				directionalVertexFunction->release();
				directionalFragmentFunction->release();
			}
			
			#pragma mark Directional lighting mask depth stencil state setup
			{
				MTL::StencilDescriptor* stencilStateDesc = MTL::StencilDescriptor::alloc()->init();
			#if LIGHT_STENCIL_CULLING
				// Stencil state setup so direction lighting fragment shader only executed on pixels
				// drawn in GBuffer stage (i.e. mask out the background/sky)
				stencilStateDesc->setStencilCompareFunction(MTL::CompareFunctionEqual);
				stencilStateDesc->setStencilFailureOperation(MTL::StencilOperationKeep);
				stencilStateDesc->setDepthFailureOperation(MTL::StencilOperationKeep);
				stencilStateDesc->setDepthStencilPassOperation(MTL::StencilOperationKeep);
				stencilStateDesc->setReadMask(0xFF);
				stencilStateDesc->setWriteMask(0x0);
			#endif
				MTL::DepthStencilDescriptor* depthStencilDesc = MTL::DepthStencilDescriptor::alloc()->init();
				depthStencilDesc->setLabel(NS::String::string("Deferred Directional Lighting", NS::ASCIIStringEncoding));
				depthStencilDesc->setDepthWriteEnabled(false);
				depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionAlways);
				depthStencilDesc->setFrontFaceStencil(stencilStateDesc);
				depthStencilDesc->setBackFaceStencil(stencilStateDesc);

				directionalLightDepthStencilState = metalDevice->newDepthStencilState(depthStencilDesc);
				
				depthStencilDesc->release();
				stencilStateDesc->release();
			}
		}

        // Setup objects for shadow pass
        {
            MTL::PixelFormat shadowMapPixelFormat = MTL::PixelFormatDepth16Unorm;

            #pragma mark shadow pass render pipeline setup
            {
                MTL::Function* shadowVertexFunction = metalDefaultLibrary->newFunction(NS::String::string("shadow_vertex", NS::ASCIIStringEncoding));

                assert(shadowVertexFunction && "Failed to load shadow_vertex shader");

                MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
                renderPipelineDescriptor->setLabel(NS::String::string("Shadow Gen", NS::ASCIIStringEncoding));
                renderPipelineDescriptor->setVertexDescriptor(nullptr);
                renderPipelineDescriptor->setVertexFunction(shadowVertexFunction);
                renderPipelineDescriptor->setFragmentFunction(nullptr);
                renderPipelineDescriptor->setDepthAttachmentPixelFormat(shadowMapPixelFormat);

                shadowPipelineState = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
                
                assert(error == nil && "Failed to create shadow map render pipeline state");

                renderPipelineDescriptor->release();
                shadowVertexFunction->release();
            }

            #pragma mark Shadow pass depth state setup
            {
                MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
                depthStencilDescriptor->setLabel( NS::String::string("Shadow Gen", NS::ASCIIStringEncoding));
                depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
                depthStencilDescriptor->setDepthWriteEnabled(true);
                shadowDepthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
                depthStencilDescriptor->release();
            }

            #pragma mark Shadow map setup
            {
                MTL::TextureDescriptor* shadowTextureDesc = MTL::TextureDescriptor::alloc()->init();

                shadowTextureDesc->setPixelFormat(shadowMapPixelFormat);
                shadowTextureDesc->setWidth(2048);
                shadowTextureDesc->setHeight(2048);
                shadowTextureDesc->setMipmapLevelCount(1);
                shadowTextureDesc->setResourceOptions(MTL::ResourceStorageModePrivate);
                shadowTextureDesc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

                shadowMap = metalDevice->newTexture(shadowTextureDesc);
                shadowMap->setLabel( NS::String::string("Shadow Map", NS::ASCIIStringEncoding));
                
                shadowTextureDesc->release();
            }

            #pragma mark Shadow render pass descriptor setup
            {
                shadowRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
                shadowRenderPassDescriptor->depthAttachment()->setTexture(shadowMap);
                shadowRenderPassDescriptor->depthAttachment()->setLoadAction(MTL::LoadActionClear);
                shadowRenderPassDescriptor->depthAttachment()->setStoreAction(MTL::StoreActionStore);
                shadowRenderPassDescriptor->depthAttachment()->setClearDepth(1.0);
            }

            // Calculate projection matrix to render shadows
            {
				// left, right, bottom, top, near, far
                shadowProjectionMatrix = matrix_ortho_right_hand(-23, 23, -23, 23, -53, 53);
            }
        }
    }
    
    # pragma mark Ray tracing pipeline state
    {
        
        MTL::Function* computeFunction = metalDefaultLibrary->newFunction(NS::String::string("raytracingKernel", NS::ASCIIStringEncoding));
        assert(computeFunction && "Failed to load raytracingKernel compute function!");

        raytracingPipelineState = metalDevice->newComputePipelineState(computeFunction, &error);
        assert(error == nil && "Failed to create drawing compute pipeline state!");

        computeFunction->release();
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
        mergedVertices.insert(mergedVertices.end(), mesh->vertices.begin(), mesh->vertices.end());

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

    for (const auto& mesh : meshes) {
        for (size_t i = 0; i < mesh->vertexIndices.size(); i += 3) {
            TriangleData& triangle = resourceBufferContents[triangleIndex++];

            for (size_t j = 0; j < 3; ++j) {
                size_t vertexIndex = mesh->vertexIndices[i + j];
                triangle.normals[j] = mesh->vertices[vertexIndex].normal;
                triangle.colors[j] = simd::float4{0.1, 0.2, 0.3, 0.4};
            }
        }
    }
}

void Engine::dispatchRaytracing(MTL::CommandBuffer* commandBuffer) {
    MTL::ComputeCommandEncoder* computeEncoder = commandBuffer->computeCommandEncoder();
    
    computeEncoder->setComputePipelineState(raytracingPipelineState);
    computeEncoder->setTexture(rayTracingTexture, TextureIndexRaytracing);
    computeEncoder->setBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    computeEncoder->setBuffer(resourceBuffer, 0, BufferIndexResources);
    
    computeEncoder->useResource(resourceBuffer, MTL::ResourceUsageRead);
    
    // Set acceleration structures
    for (uint i = 0; i < primitiveAccelerationStructures.size(); i++) {
        computeEncoder->setAccelerationStructure(primitiveAccelerationStructures[i], BufferIndexAccelerationStructure);
        computeEncoder->useResource(primitiveAccelerationStructures[i], MTL::ResourceUsageRead);

    }

    MTL::Size threadGroupSize = MTL::Size(16, 16, 1);
    MTL::Size gridSize = MTL::Size((rayTracingTexture->width() + threadGroupSize.width - 1) / threadGroupSize.width,
                                   (rayTracingTexture->height() + threadGroupSize.height - 1) / threadGroupSize.height, 1);

    computeEncoder->dispatchThreadgroups(gridSize, threadGroupSize);
    computeEncoder->popDebugGroup();
    computeEncoder->endEncoding();
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
	gbufferTextureDesc->setPixelFormat(normalShadowGBufferFormat);
	normalShadowGBuffer = metalDevice->newTexture(gbufferTextureDesc);
	gbufferTextureDesc->setPixelFormat(depthGBufferFormat);
	depthGBuffer = metalDevice->newTexture(gbufferTextureDesc);

    // Create depth/stencil texture
	gbufferTextureDesc->setPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
	depthStencilTexture = metalDevice->newTexture(gbufferTextureDesc);
	
	albedoSpecularGBuffer->setLabel(NS::String::string("Albedo + Shadow GBuffer", NS::ASCIIStringEncoding));
	normalShadowGBuffer->setLabel(NS::String::string("Normal + Specular GBuffer", NS::ASCIIStringEncoding));
	depthGBuffer->setLabel(NS::String::string("Depth GBuffer", NS::ASCIIStringEncoding));
	depthStencilTexture->setLabel(NS::String::string("Depth-Stencil Texture", NS::ASCIIStringEncoding));

	gbufferTextureDesc->release();
	
	viewRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

	// Set up render pass descriptor attachments
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoSpecularGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalShadowGBuffer);
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
}

void Engine::updateRenderPassDescriptor() {
	// Update all render pass descriptor attachments with resized textures
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetAlbedo)->setTexture(albedoSpecularGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetNormal)->setTexture(normalShadowGBuffer);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetDepth)->setTexture(depthGBuffer);

	// Update depth/stencil attachment
	viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
	viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
}

void Engine::calculateCascadeSplits(float nearClip, float farClip, float* splits) {
	// Using practical split scheme: https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch10.html
	const float lambda = 0.5f; // Balance between logarithmic and uniform
	
	for (int i = 0; i < SHADOW_CASCADE_COUNT; i++) {
		float p = (i + 1) / float(SHADOW_CASCADE_COUNT);
		float log = nearClip * pow(farClip / nearClip, p);
		float uniform = nearClip + (farClip - nearClip) * p;
		float d = lambda * (log - uniform) + uniform;
		// d = λ*log + (1 - λ)*uni => λ*log + uni - λ*uni => λ*(log - uni) + uni
		splits[i] = d;
	}
}

void Engine::setupShadowCascades() {
	MTL::TextureDescriptor* shadowTextureDesc = MTL::TextureDescriptor::alloc()->init();
	shadowTextureDesc->setPixelFormat(MTL::PixelFormatDepth32Float);
	shadowTextureDesc->setWidth(2048);
	shadowTextureDesc->setHeight(2048);
	shadowTextureDesc->setMipmapLevelCount(1);
	shadowTextureDesc->setResourceOptions(MTL::ResourceStorageModePrivate);
	shadowTextureDesc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
	
	for (int i = 0; i < SHADOW_CASCADE_COUNT; i++) {
		shadowCascadeMaps[i] = metalDevice->newTexture(shadowTextureDesc);
		shadowCascadeMaps[i]->setLabel(NS::String::string("Shadow Cascade Map", NS::ASCIIStringEncoding));
		
		shadowCascadeRenderPassDescriptors[i] = MTL::RenderPassDescriptor::alloc()->init();
		shadowCascadeRenderPassDescriptors[i]->depthAttachment()->setTexture(shadowCascadeMaps[i]);
		shadowCascadeRenderPassDescriptors[i]->depthAttachment()->setLoadAction(MTL::LoadActionClear);
		shadowCascadeRenderPassDescriptors[i]->depthAttachment()->setStoreAction(MTL::StoreActionStore);
		shadowCascadeRenderPassDescriptors[i]->depthAttachment()->setClearDepth(1.0);
	}
	
	shadowTextureDesc->release();
}

simd::float4x4 Engine::calculateCascadeProjectionMatrix(const simd::float3* frustumCorners, float nearDist, float farDist) {
	// First calculate frustum center
	simd::float3 frustumCenter = simd::float3{0.0f, 0.0f, 0.0f};
	for (int j = 0; j < 8; j++) {
		frustumCenter += frustumCorners[j];
	}

	frustumCenter = frustumCenter / 8.0f;

	// Calculate radius (maximum distance from center to any corner)
	float radius = 0.0f;
	for (int j = 0; j < 8; j++) {
		float distance = simd::length(frustumCorners[j] - frustumCenter);
		radius = std::max(radius, distance);
	}
	// Round up radius to help reduce shadow swimming
	radius = std::ceil(radius * 16.0f) / 16.0f;

	simd::float3 max = radius;
	simd::float3 min = -max;

	for (int i = 0; i < 8; i++) {
		min = simd::min(min, frustumCorners[i]);
		max = simd::max(max, frustumCorners[i]);
	}

	// Padding to avoid edge artifacts
	simd::float3 scale = (max - min) * 0.1f;
	min -= scale;
	max += scale;

	return matrix_ortho_right_hand(min.x, max.x,
								   min.y, max.y,
								   min.z, max.z - min.z);
}

void Engine::drawMeshes(MTL::RenderCommandEncoder* renderCommandEncoder) {
	renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
    
    for (int i = 0; i < meshes.size(); i++) {
        //	renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines);
        renderCommandEncoder->setVertexBuffer(meshes[i]->vertexBuffer, 0, BufferIndexVertexData);
        
        matrix_float4x4 modelMatrix = matrix4x4_translation(0.0f, 0.0f, 0.0f);
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

void Engine::drawShadow(MTL::CommandBuffer* commandBuffer)
{
    MTL::RenderCommandEncoder* renderCommandEncoder = commandBuffer->renderCommandEncoder(shadowRenderPassDescriptor);

    renderCommandEncoder->setLabel( NS::String::string("Shadow Map Pass", NS::ASCIIStringEncoding));

    renderCommandEncoder->setRenderPipelineState(shadowPipelineState);
    renderCommandEncoder->setDepthStencilState(shadowDepthStencilState);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    renderCommandEncoder->setDepthBias(0.015, 7, 0.02);
    renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);

	drawMeshes(renderCommandEncoder);

    renderCommandEncoder->endEncoding();
}

//void Engine::drawShadow(MTL::CommandBuffer* commandBuffer) {
//	for (int i = 0; i < SHADOW_CASCADE_COUNT; i++) {
//		MTL::RenderCommandEncoder* shadowPass =
//			commandBuffer->renderCommandEncoder(shadowCascadeRenderPassDescriptors[i]);
//			
//		if (shadowPass) {
//			shadowPass->setLabel(NS::String::string("Shadow Pass", NS::ASCIIStringEncoding));
//			shadowPass->setRenderPipelineState(shadowPipelineState);
//			shadowPass->setDepthStencilState(shadowDepthStencilState);
//			
//			// Set the current cascade index for the shader
//			shadowPass->setVertexBytes(&i, sizeof(int), 30);
//			
//			// Draw meshes
//			drawMeshes(shadowPass);
//			
//			shadowPass->endEncoding();
//		}
//	}
//}

void Engine::drawGBuffer(MTL::RenderCommandEncoder* renderCommandEncoder)
{
	renderCommandEncoder->pushDebugGroup(NS::String::string("Draw G-Buffer", NS::ASCIIStringEncoding));
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
	renderCommandEncoder->setRenderPipelineState(GBufferPipelineState);
	renderCommandEncoder->setDepthStencilState(GBufferDepthStencilState);
	renderCommandEncoder->setStencilReferenceValue(128);
    renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
	renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
	renderCommandEncoder->setFragmentTexture(shadowMap, TextureIndexShadow);

	drawMeshes(renderCommandEncoder);
	renderCommandEncoder->popDebugGroup();
}

/// Draw the directional ("sun") light in deferred pass.  Use stencil buffer to limit execution
/// of the shader to only those pixels that should be lit
void Engine::drawDirectionalLight(MTL::RenderCommandEncoder* renderCommandEncoder)
{
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
	renderCommandEncoder->setStencilReferenceValue(128);

	renderCommandEncoder->setRenderPipelineState(directionalLightPipelineState);
	renderCommandEncoder->setDepthStencilState(directionalLightDepthStencilState);
	renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
	renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);

	// Draw full screen triangle
	renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)3);
}

void Engine::draw() {
	// First command buffer for shadow pass
	MTL::CommandBuffer* shadowCommandBuffer = beginFrame(false);
	shadowCommandBuffer->setLabel(NS::String::string("Shadow Commands", NS::ASCIIStringEncoding));
	drawShadow(shadowCommandBuffer);
	shadowCommandBuffer->commit();
	
	// Second command buffer for GBuffer and lighting passes
	MTL::CommandBuffer* commandBuffer = beginDrawableCommands();
	commandBuffer->setLabel(NS::String::string("Deferred Rendering Commands", NS::ASCIIStringEncoding));
    
    dispatchRaytracing(commandBuffer);
	
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetLighting)->setTexture(metalDrawable->texture());
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetLighting)->setLoadAction(MTL::LoadActionClear);
	viewRenderPassDescriptor->colorAttachments()->object(RenderTargetLighting)->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
	viewRenderPassDescriptor->depthAttachment()->setTexture(depthStencilTexture);
	viewRenderPassDescriptor->stencilAttachment()->setTexture(depthStencilTexture);
	
	// G-Buffer pass
	MTL::RenderCommandEncoder* gBufferEncoder = commandBuffer->renderCommandEncoder(viewRenderPassDescriptor);
	if (gBufferEncoder) {
		drawGBuffer(gBufferEncoder);
		
		drawDirectionalLight(gBufferEncoder);
		
		gBufferEncoder->endEncoding();
	}
	
	// End the frame
	endFrame(commandBuffer, metalDrawable);
}
