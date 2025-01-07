#include "engine.hpp"

Engine::Engine()
: camera(simd::float3{0.0f, 0.0f, 3.0f})
, lastFrame(0.0f)
, frameNumber(0)
, currentFrameIndex(0) {
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
    createBuffers();
    createDefaultLibrary();
    createRenderPipelines();
    createDepthTexture();
    createRenderPassDescriptor();
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
    delete mesh;
	
	for(uint8_t i = 0; i < MaxFramesInFlight; i++) {
		frameDataBuffers[i]->release();
    }
	
	defaultVertexDescriptor->release();
    depthTexture->release();
	shadowMap->release();
    renderPassDescriptor->release();
    metalRenderPSO->release();
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
    if (depthTexture) {
        depthTexture->release();
        depthTexture = nullptr;
    }
    createDepthTexture();
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
    
    /// Perform operations necessary to obtain a command buffer for rendering to the drawable. By
    /// endoding commands that are not dependant on the drawable in a separate command buffer, Metal
    /// can begin executing encoded commands for the frame (commands from the previous command buffer)
    /// before a drawable for this frame becomes available.
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
	
    std::string smgPath = std::string(SCENES_PATH) + "/sponza/sponza.obj";
	mesh = new Mesh(smgPath.c_str(), metalDevice, defaultVertexDescriptor);
	
//	GLTFLoader gltfLoader(metalDevice);
//	std::string modelPath = std::string(SCENES_PATH) + "/DamagedHelmet/DamagedHelmet.gltf";
//	auto gltfModel = gltfLoader.loadModel(modelPath);
//	
//	// Create mesh from the loaded data
//	mesh = new Mesh(metalDevice,
//				  gltfModel.vertices.data(),
//				  gltfModel.vertices.size(),
//				  gltfModel.indices.data(),
//				  gltfModel.indices.size());
}

void Engine::createBuffers() {
    
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

    frameData->projection_matrix = camera.getProjectionMatrix(aspectRatio);
    frameData->projection_matrix_inverse = matrix_invert(frameData->projection_matrix);
    frameData->view_matrix = camera.getViewMatrix();

    // Set screen dimensions
    frameData->framebuffer_width = (uint)metalLayer.drawableSize.width;
    frameData->framebuffer_height = (uint)metalLayer.drawableSize.height;

    frameData->sun_color = simd_make_float4(1.0, 1.0, 1.0, 1.0);
	
	
	float skyRotation = frameNumber * 0.005f - (M_PI_4*3);

	float3 skyRotationAxis = {0, 1, 0};
	float4x4 skyModelMatrix = matrix4x4_rotation(skyRotation, skyRotationAxis);
	frameData->sky_modelview_matrix = skyModelMatrix;

	// Update directional light color
	float4 sun_color = {0.5, 0.5, 0.5, 1.0};
	frameData->sun_color = sun_color;
	frameData->sun_specular_intensity = 1;

	// Update sun direction in view space
	float4 sunModelPosition = {-0.25, -0.5, 1.0, 0.0};
	float4 sunWorldPosition = skyModelMatrix * sunModelPosition;
	float4 sunWorldDirection = -sunWorldPosition;

	frameData->sun_eye_direction = /*frameData->view_matrix * */ sunWorldDirection; // I will need to change this in deferred?

	{
		float4 directionalLightUpVector = {0.0, 1.0, 1.0, 1.0};

		directionalLightUpVector = skyModelMatrix * directionalLightUpVector;
		directionalLightUpVector.xyz = normalize(directionalLightUpVector.xyz);

		float4x4 shadowViewMatrix = matrix_look_at_left_hand(sunWorldDirection.xyz / 10, // adjust based on scene scale
																 (float3){0,0,0},
																 directionalLightUpVector.xyz);

		// If scene changes multiply the model with shadowViewMatrx
		frameData->scene_model_matrix = matrix4x4_translation(0.0f, 0.0f, 0.0f); // sponza is set in this position
		frameData->scene_modelview_matrix = frameData->view_matrix * frameData->scene_model_matrix;
		frameData->scene_normal_matrix = matrix3x3_upper_left(frameData->scene_model_matrix);
	}

	{
		// When calculating texture coordinates to sample from shadow map, flip the y/t coordinate and
		// convert from the [-1, 1] range of clip coordinates to [0, 1] range of
		// used for texture sampling
		float4x4 shadowScale = matrix4x4_scale(0.5f, -0.5f, 1.0);
		float4x4 shadowTranslate = matrix4x4_translation(0.5, 0.5, 0);
		float4x4 shadowTransform = shadowTranslate * shadowScale;

		frameData->shadow_mvp_xform_matrix = shadowTransform * frameData->shadow_mvp_matrix;
	}
}

void Engine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void Engine::createRenderPipelines() {
    NS::Error* error;

    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("vertexShader", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("fragmentShader", NS::ASCIIStringEncoding));
        assert(fragmentShader);

        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setVertexDescriptor(defaultVertexDescriptor);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        assert(renderPipelineDescriptor);
        MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
        renderPipelineDescriptor->setSampleCount(1);
        renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth16Unorm);

        metalRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

        assert(error == nil && "Failed to create view render pipeline state");

        MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
        depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
        depthStencilDescriptor->setDepthWriteEnabled(true);
        depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
}

void Engine::createDepthTexture() {
	MTL::TextureDescriptor* depthTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
	depthTextureDescriptor->setPixelFormat(MTL::PixelFormatDepth16Unorm);
	depthTextureDescriptor->setWidth(metalLayer.drawableSize.width);
	depthTextureDescriptor->setHeight(metalLayer.drawableSize.height);
	depthTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget);
	depthTextureDescriptor->setSampleCount(1);

	depthTexture = metalDevice->newTexture(depthTextureDescriptor);
	depthTextureDescriptor->release();
}

void Engine::createRenderPassDescriptor() {
	renderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

	MTL::RenderPassColorAttachmentDescriptor* colorAttachment = renderPassDescriptor->colorAttachments()->object(0);
	MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = renderPassDescriptor->depthAttachment();

	colorAttachment->setTexture(metalDrawable->texture());
	colorAttachment->setLoadAction(MTL::LoadActionClear);
	colorAttachment->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
	colorAttachment->setStoreAction(MTL::StoreActionStore);

	depthAttachment->setTexture(depthTexture);
	depthAttachment->setLoadAction(MTL::LoadActionClear);
	depthAttachment->setStoreAction(MTL::StoreActionDontCare);
	depthAttachment->setClearDepth(1.0);
}

void Engine::updateRenderPassDescriptor() {
	renderPassDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
	renderPassDescriptor->depthAttachment()->setTexture(depthTexture);
}

void Engine::drawScene(MTL::RenderCommandEncoder* renderCommandEncoder) {
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
	
	//    renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines);
	renderCommandEncoder->setDepthStencilState(depthStencilState);
	renderCommandEncoder->setVertexBuffer(mesh->vertexBuffer, 0, 0);
		
	matrix_float4x4 modelMatrix = matrix4x4_translation(0.0f, 0.0f, 0.0f);
	
	// Send matrices to shaders
	renderCommandEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), 1);
    renderCommandEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, 2);
		
    // Set up the light source
    renderCommandEncoder->setFragmentBuffer(frameDataBuffers[currentFrameIndex], 0, 0);
    renderCommandEncoder->setFragmentTexture(mesh->diffuseTextures, 1);
	renderCommandEncoder->setFragmentTexture(mesh->normalTextures, 2);
    renderCommandEncoder->setFragmentBuffer(mesh->diffuseTextureInfos, 0, 3);
	renderCommandEncoder->setFragmentBuffer(mesh->normalTextureInfos, 0, 4);
    
    // Tell the input assembler to draw triangles
    MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
    renderCommandEncoder->drawIndexedPrimitives(typeTriangle, mesh->indexCount, MTL::IndexTypeUInt32, mesh->indexBuffer, 0);
}

void Engine::drawMeshes(MTL::RenderCommandEncoder* renderCommandEncoder) {
	renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
	
	renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines);
	renderCommandEncoder->setDepthStencilState(depthStencilState);
	renderCommandEncoder->setVertexBuffer(mesh->vertexBuffer, 0, 0);
	
	matrix_float4x4 modelMatrix = matrix4x4_translation(0.0f, 0.0f, 0.0f);
	renderCommandEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), 1);

	// Set any textures read/sampled from the render pipeline
	renderCommandEncoder->setFragmentTexture(mesh->diffuseTextures, TextureIndexBaseColor);
	renderCommandEncoder->setFragmentTexture(mesh->normalTextures, TextureIndexNormal);
	renderCommandEncoder->setFragmentBuffer(mesh->diffuseTextureInfos, 0, 3);
	renderCommandEncoder->setFragmentBuffer(mesh->normalTextureInfos, 0, 4);
	
	MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
	renderCommandEncoder->drawIndexedPrimitives(typeTriangle, mesh->indexCount, MTL::IndexTypeUInt32, mesh->indexBuffer, 0);
}

void Engine::draw() {
	MTL::CommandBuffer* commandBuffer = beginFrame(false);
	
	// Forward rendering pass
	updateRenderPassDescriptor();
	MTL::RenderCommandEncoder* renderCommandEncoder = commandBuffer->renderCommandEncoder(renderPassDescriptor);
	renderCommandEncoder->setRenderPipelineState(metalRenderPSO);
	drawScene(renderCommandEncoder);
	renderCommandEncoder->endEncoding();
	
	// End the frame
	endFrame(commandBuffer, metalDrawable);
}
