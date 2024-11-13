#include "engine.hpp"

Engine::Engine()
: camera(simd::float3{0.0f, 0.0f, 3.0f})
, lastFrame(0.0f)
, frameNumber(0)
, currentFrameIndex(0)
, sunAzimuth(0)
, sunAltitude(45) {
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
    createRenderPipeline();
    createDepthAndMSAATextures();
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
	
    msaaRenderTargetTexture->release();
    depthTexture->release();
    renderPassDescriptor->release();
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
    if (msaaRenderTargetTexture) {
        msaaRenderTargetTexture->release();
        msaaRenderTargetTexture = nullptr;
    }
    if (depthTexture) {
        depthTexture->release();
        depthTexture = nullptr;
    }
    createDepthAndMSAATextures();
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

    // The idea is begin frame for the drawShadow, commit, and then draw the drawables
    // After this moment we are supposed to draw the g-buffer geometry later on
    // return command buffer here and after you drawShadow commit it

    // then create another command buffer for g-buffer
    // MTL::CommandBuffer* commandBuffer = metalCommandQueue->commandBuffer();

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
    std::string smgPath = std::string(SCENES_PATH) + "/sponza/sponza.obj";
    mesh = new Mesh(smgPath.c_str(), metalDevice);
	
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

    sunAzimuth += 0.5f; // Increase the azimuth (horizontal angle) over time
	if (sunAzimuth >= 360.0f) {
		sunAzimuth -= 360.0f;
	}

    sunDirection = float4{
        cosf(sunAzimuth * M_PI / 180.0f) * cosf(sunAltitude * M_PI / 180.0f),
		sinf(sunAltitude * M_PI / 180.0f),
		sinf(sunAzimuth * M_PI / 180.0f) * cosf(sunAltitude * M_PI / 180.0f),
        0.0
    };

    frameData->sunDirection = sunDirection;
    frameData->sunColor = simd_make_float4(1.0, 1.0, 1.0, 1.0);
}

void Engine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void Engine::createRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("vertexShader", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("fragmentShader", NS::ASCIIStringEncoding));
    assert(fragmentShader);

    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    assert(renderPipelineDescriptor);
    MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
    renderPipelineDescriptor->setSampleCount(sampleCount);
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);

    NS::Error* error;
    metalRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

    if (metalRenderPSO == nil) {
        std::cout << "Error creating render pipeline state: " << error << std::endl;
        std::exit(0);
    }

    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);

    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void Engine::createDepthAndMSAATextures() {
    MTL::TextureDescriptor* msaaTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    msaaTextureDescriptor->setTextureType(MTL::TextureType2DMultisample);
    msaaTextureDescriptor->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    msaaTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    msaaTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    msaaTextureDescriptor->setSampleCount(sampleCount);
    msaaTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget);

    msaaRenderTargetTexture = metalDevice->newTexture(msaaTextureDescriptor);

    MTL::TextureDescriptor* depthTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    depthTextureDescriptor->setTextureType(MTL::TextureType2DMultisample);
    depthTextureDescriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
    depthTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    depthTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    depthTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget);
    depthTextureDescriptor->setSampleCount(sampleCount);

    depthTexture = metalDevice->newTexture(depthTextureDescriptor);

    msaaTextureDescriptor->release();
    depthTextureDescriptor->release();
}

void Engine::createRenderPassDescriptor() {
    renderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

    MTL::RenderPassColorAttachmentDescriptor* colorAttachment = renderPassDescriptor->colorAttachments()->object(0);
    MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = renderPassDescriptor->depthAttachment();

    colorAttachment->setTexture(msaaRenderTargetTexture);
    colorAttachment->setResolveTexture(metalDrawable->texture());
    colorAttachment->setLoadAction(MTL::LoadActionClear);
    colorAttachment->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
    colorAttachment->setStoreAction(MTL::StoreActionMultisampleResolve);

    depthAttachment->setTexture(depthTexture);
    depthAttachment->setLoadAction(MTL::LoadActionClear);
    depthAttachment->setStoreAction(MTL::StoreActionDontCare);
    depthAttachment->setClearDepth(1.0);
}

void Engine::updateRenderPassDescriptor() {
    renderPassDescriptor->colorAttachments()->object(0)->setTexture(msaaRenderTargetTexture);
    renderPassDescriptor->colorAttachments()->object(0)->setResolveTexture(metalDrawable->texture());
    renderPassDescriptor->depthAttachment()->setTexture(depthTexture);
}

void Engine::drawScene(MTL::RenderCommandEncoder* renderCommandEncoder) {
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
	renderCommandEncoder->setCullMode(MTL::CullModeBack);
	
	//    renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines);
	renderCommandEncoder->setRenderPipelineState(metalRenderPSO);
	renderCommandEncoder->setDepthStencilState(depthStencilState);
	renderCommandEncoder->setVertexBuffer(mesh->vertexBuffer, 0, 0);
	
	float aspectRatio = metalDrawable->layer()->drawableSize().width / metalDrawable->layer()->drawableSize().height;
	
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

void Engine::draw() {
    MTL::CommandBuffer* commandBuffer = beginFrame(false);
    updateRenderPassDescriptor();
    MTL::RenderCommandEncoder* renderCommandEncoder = commandBuffer->renderCommandEncoder(renderPassDescriptor);
    drawScene(renderCommandEncoder);
    renderCommandEncoder->endEncoding();
    endFrame(commandBuffer, metalDrawable);
}