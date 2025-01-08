#include "engine.hpp"

Engine::Engine()
: camera(simd::float3{7.0f, 5.0f, 0.0f})
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
    createTextures();
    createRenderPassDescriptor();
    createAccelerationStructureWithDescriptors();
    setupMeshResources();
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
    
    resourceBuffer->release();
    for (auto& resources : meshResources) {
        resources.vertexNormalBuffer->release();
        resources.indexBuffer->release();
    }
    meshResources.clear();
	
	defaultVertexDescriptor->release();
    outputTexture->release();
    renderPassDescriptor->release();
    renderPipelineState->release();
    raytracingPipelineState->release();
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
    if (outputTexture) {
        outputTexture->release();
        outputTexture = nullptr;
    }
    createTextures();
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
	meshes.push_back(new Mesh(smgPath.c_str(), metalDevice, defaultVertexDescriptor));
	
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
    
    frameData->projection_matrix            = camera.getProjectionMatrix(aspectRatio);
    frameData->projection_matrix_inverse    = matrix_invert(frameData->projection_matrix);
    frameData->view_matrix                  = camera.getViewMatrix();
    
    frameData->cameraUp         = float4{camera.up.x,       camera.up.y,        camera.up.z, 1.0f};
    frameData->cameraRight      = float4{camera.right.x,    camera.right.y,     camera.right.z, 1.0f};
    frameData->cameraForward    = float4{camera.front.x,    camera.front.y,     camera.front.z, 1.0f};
    frameData->cameraPosition   = float4{camera.position.x, camera.position.y,  camera.position.z, 1.0f};

    // Set screen dimensions
    frameData->framebuffer_width    = (uint)metalLayer.drawableSize.width;
    frameData->framebuffer_height   = (uint)metalLayer.drawableSize.height;

    frameData->sun_color = simd_make_float4(1.0, 1.0, 1.0, 1.0);
	
	
	float skyRotation = frameNumber * 0.005f - (M_PI_4*3);

	float3 skyRotationAxis  = {0, 1, 0};
	float4x4 skyModelMatrix = matrix4x4_rotation(skyRotation, skyRotationAxis);

	// Update directional light color
	float4 sun_color                    = {0.5, 0.5, 0.5, 1.0};
	frameData->sun_color                = sun_color;
	frameData->sun_specular_intensity   = 1;

	// Update sun direction in view space
	float4 sunModelPosition     = {-0.25, -0.5, 1.0, 0.0};
	float4 sunWorldPosition     = skyModelMatrix * sunModelPosition;
	float4 sunWorldDirection    = -sunWorldPosition;

	frameData->sun_eye_direction = sunWorldDirection;
}

void Engine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void Engine::createRenderPipelines() {
    NS::Error* error;

    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("vertex_function", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("fragment_function", NS::ASCIIStringEncoding));
        assert(fragmentShader);

        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setVertexDescriptor(defaultVertexDescriptor);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        assert(renderPipelineDescriptor);
        MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
        renderPipelineDescriptor->setSampleCount(1);

        renderPipelineState = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

        assert(error == nil && "Failed to create view render pipeline state");

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    
    {
        MTL::Function* computeFunction = metalDefaultLibrary->newFunction(NS::String::string("raytracingKernel", NS::ASCIIStringEncoding));
        assert(computeFunction && "Failed to load raytracingKernel compute function!");

        raytracingPipelineState = metalDevice->newComputePipelineState(computeFunction, &error);
        assert(error == nil && "Failed to create drawing compute pipeline state!");

        computeFunction->release();
    }
}

void Engine::createTextures() {
    MTL::TextureDescriptor* outputTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    outputTextureDescriptor->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    outputTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    outputTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    outputTextureDescriptor->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    outputTextureDescriptor->setSampleCount(1);

    outputTexture = metalDevice->newTexture(outputTextureDescriptor);

    outputTextureDescriptor->release();
}

void Engine::createRenderPassDescriptor() {
	renderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

	MTL::RenderPassColorAttachmentDescriptor* colorAttachment = renderPassDescriptor->colorAttachments()->object(0);

	colorAttachment->setTexture(metalDrawable->texture());
	colorAttachment->setLoadAction(MTL::LoadActionClear);
	colorAttachment->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
	colorAttachment->setStoreAction(MTL::StoreActionStore);
}

void Engine::createAccelerationStructureWithDescriptors() {
    // Create a separate command queue for acceleration structure building
    MTL::CommandQueue* commandQueue = metalDevice->newCommandQueue();
    MTL::CommandBuffer* commandBuffer = commandQueue->commandBuffer();
    
    for (uint i = 0; i < meshes.size(); i++) {
        // Create triangle descriptors
        MTL::AccelerationStructureTriangleGeometryDescriptor* geometryDescriptor = MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();
          
        geometryDescriptor->setVertexBuffer(meshes[i]->vertexBuffer);
        geometryDescriptor->setVertexStride(sizeof(Vertex));
        geometryDescriptor->setVertexFormat(MTL::AttributeFormatFloat3);

        geometryDescriptor->setIndexBuffer(meshes[i]->indexBuffer);
        geometryDescriptor->setIndexType(MTL::IndexTypeUInt32);
        geometryDescriptor->setTriangleCount(meshes[i]->triangleCount);
        
        NS::Array* geometryDescriptors = NS::Array::array(geometryDescriptor);
        
        // Set the triangle descriptors
        MTL::PrimitiveAccelerationStructureDescriptor* accelerationStructureDescriptor = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
        accelerationStructureDescriptor->setGeometryDescriptors(geometryDescriptors);
        
        // Allocate size for the acceleration structure
        MTL::AccelerationStructureSizes sizes = metalDevice->accelerationStructureSizes(accelerationStructureDescriptor);
        MTL::AccelerationStructure* accelerationStructure = metalDevice->newAccelerationStructure(sizes.accelerationStructureSize);
        
        MTL::Buffer* scratchBuffer = metalDevice->newBuffer(sizes.buildScratchBufferSize, MTL::ResourceStorageModePrivate);
        std::string labelStr = "scratchBuffer: " + std::to_string(i);
        NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
        scratchBuffer->setLabel(label);
        
        MTL::AccelerationStructureCommandEncoder* commandEncoder = commandBuffer->accelerationStructureCommandEncoder();
        
        commandEncoder->buildAccelerationStructure(accelerationStructure, accelerationStructureDescriptor, scratchBuffer, 0);
        commandEncoder->endEncoding();
        
        primitiveAccelerationStructures.push_back(accelerationStructure);
        
        geometryDescriptor->release();
        geometryDescriptors->release();
        accelerationStructureDescriptor->release();
        scratchBuffer->release();
    }
    
    commandBuffer->commit();
    commandBuffer->waitUntilCompleted();
    
    commandBuffer->release();
    commandQueue->release();
}

void Engine::updateRenderPassDescriptor() {
	renderPassDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
}

void Engine::setupMeshResources() {
    resourcesStride = sizeof(MeshResources);

    resourceBuffer = metalDevice->newBuffer(resourcesStride * meshes.size(), MTL::ResourceStorageModeShared);
    resourceBuffer->setLabel(NS::String::string("ResourceBuffer", NS::ASCIIStringEncoding));
    char* resourceBufferContents = (char*)resourceBuffer->contents();

    for (size_t i = 0; i < meshes.size(); i++) {
        MeshResources resources;

        resources.vertexNormalBuffer = metalDevice->newBuffer(meshes[i]->vertices.size() * sizeof(float3), MTL::ResourceStorageModeShared);
        std::string labelStr = "vertexNormalBuffer: " + std::to_string(i);
        NS::String* label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
        resources.vertexNormalBuffer->setLabel(label);
        
        float3* normalData = (float3*)resources.vertexNormalBuffer->contents();
        for (size_t j = 0; j < meshes[i]->vertices.size(); j++) {
            normalData[j] = normalize(meshes[i]->vertices[j].normal.xyz);
        }

        resources.indexBuffer = metalDevice->newBuffer(meshes[i]->vertexIndices.size() * sizeof(uint32_t), MTL::ResourceStorageModeShared);
        labelStr = "indexBuffer: " + std::to_string(i);
        label = NS::String::string(labelStr.c_str(), NS::ASCIIStringEncoding);
        resources.indexBuffer->setLabel(label);
        
        uint32_t* indexData = (uint32_t*)resources.indexBuffer->contents();
        memcpy(indexData, meshes[i]->vertexIndices.data(), meshes[i]->vertexIndices.size() * sizeof(uint32_t));

        memcpy(resourceBufferContents + i * resourcesStride, &resources, sizeof(MeshResources));

        meshResources.push_back(resources);
    }
}

void Engine::dispatchRaytracing(MTL::CommandBuffer* commandBuffer) {
    MTL::ComputeCommandEncoder* computeEncoder = commandBuffer->computeCommandEncoder();
    
    computeEncoder->setComputePipelineState(raytracingPipelineState);
    computeEncoder->setTexture(outputTexture, 0);
    computeEncoder->setBuffer(frameDataBuffers[currentFrameIndex], 0, BufferIndexFrameData);
    computeEncoder->setBuffer(resourceBuffer, 0, BufferIndexResources);
    
    // Set acceleration structures
    for (uint i = 0; i < primitiveAccelerationStructures.size(); i++) {
        computeEncoder->setAccelerationStructure(primitiveAccelerationStructures[i], BufferIndexAccelerationStructure);
    }

    MTL::Size threadGroupSize = MTL::Size(16, 16, 1);
    MTL::Size gridSize = MTL::Size((outputTexture->width() + threadGroupSize.width - 1) / threadGroupSize.width,
                                   (outputTexture->height() + threadGroupSize.height - 1) / threadGroupSize.height, 1);

    computeEncoder->dispatchThreadgroups(gridSize, threadGroupSize);
    computeEncoder->popDebugGroup();
    computeEncoder->endEncoding();
}

void Engine::draw() {
    MTL::CommandBuffer* commandBuffer = beginFrame(false);
    
    dispatchRaytracing(commandBuffer);
    
    updateRenderPassDescriptor();
    
    MTL::RenderCommandEncoder* renderEncoder = commandBuffer->renderCommandEncoder(renderPassDescriptor);

    renderEncoder->setRenderPipelineState(renderPipelineState);
    renderEncoder->setFragmentTexture(outputTexture, 0);
    renderEncoder->setVertexBuffer(frameDataBuffers[currentFrameIndex], 0, 0);
    renderEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, 0, 3, 1);
    
    renderEncoder->endEncoding();

    endFrame(commandBuffer, metalDrawable);
}
