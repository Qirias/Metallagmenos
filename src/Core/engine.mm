#include "engine.hpp"

void MTLEngine::init() {
    initDevice();
    initWindow();

    createCommandQueue();
    loadMeshes();
    createBuffers();
    createDefaultLibrary();
    createRenderPipeline();
    createLightSourceRenderPipeline();
    createDepthAndMSAATextures();
    createRenderPassDescriptor();
}

void MTLEngine::run() {
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

void MTLEngine::cleanup() {
    glfwTerminate();
    delete mesh;
 
    msaaRenderTargetTexture->release();
    depthTexture->release();
    renderPassDescriptor->release();
    metalDevice->release();
}

void MTLEngine::initDevice() {
    metalDevice = MTL::CreateSystemDefaultDevice();
}

void MTLEngine::frameBufferSizeCallback(GLFWwindow *window, int width, int height) {
    MTLEngine* engine = (MTLEngine*)glfwGetWindowUserPointer(window);
    engine->resizeFrameBuffer(width, height);
}

void MTLEngine::mouseButtonCallback(GLFWwindow* window, int button, int action, int mods) {
    MTLEngine* engine = (MTLEngine*)glfwGetWindowUserPointer(window);
    engine->camera.processMouseButton(window, button, action);
}

void MTLEngine::cursorPosCallback(GLFWwindow* window, double xpos, double ypos) {
    MTLEngine* engine = (MTLEngine*)glfwGetWindowUserPointer(window);
    engine->camera.processMouseMovement(xpos, ypos);
}

void MTLEngine::resizeFrameBuffer(int width, int height) {
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

void MTLEngine::initWindow() {
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

void MTLEngine::loadMeshes() {
    std::string smgPath = std::string(SCENES_PATH) + "/sponza/sponza.obj";
    mesh = new Mesh(smgPath.c_str(), metalDevice);
//	
	
     GLTFLoader gltfLoader(metalDevice);
	
//     std::string modelPath = std::string(SCENES_PATH) + "/DamagedHelmet/DamagedHelmet.gltf";
//     auto gltfModel = gltfLoader.loadModel(modelPath);
//	
//	// Create mesh from the loaded data
//	mesh = new Mesh(metalDevice,
//				  gltfModel.vertices.data(),
//				  gltfModel.vertices.size(),
//				  gltfModel.indices.data(),
//				  gltfModel.indices.size());
	

    VertexData lightSource[] = {
        // Front face            // Normals
        {{-0.5,-0.5, 0.5, 1.0}, {0.0, 0.0, 1.0, 1.0}},
        {{ 0.5,-0.5, 0.5, 1.0}, {0.0, 0.0, 1.0, 1.0}},
        {{ 0.5, 0.5, 0.5, 1.0}, {0.0, 0.0, 1.0, 1.0}},
        {{ 0.5, 0.5, 0.5, 1.0}, {0.0, 0.0, 1.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0, 1.0, 1.0}},
        {{-0.5,-0.5, 0.5, 1.0}, {0.0, 0.0, 1.0, 1.0}},
        
        // Back face
        {{ 0.5,-0.5,-0.5, 1.0}, {0.0, 0.0,-1.0, 1.0}},
        {{-0.5,-0.5,-0.5, 1.0}, {0.0, 0.0,-1.0, 1.0}},
        {{-0.5, 0.5,-0.5, 1.0}, {0.0, 0.0,-1.0, 1.0}},
        {{-0.5, 0.5,-0.5, 1.0}, {0.0, 0.0,-1.0, 1.0}},
        {{ 0.5, 0.5,-0.5, 1.0}, {0.0, 0.0,-1.0, 1.0}},
        {{ 0.5,-0.5,-0.5, 1.0}, {0.0, 0.0,-1.0, 1.0}},

        // Top face
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 1.0, 0.0, 1.0}},
        {{ 0.5, 0.5, 0.5, 1.0}, {0.0, 1.0, 0.0, 1.0}},
        {{ 0.5, 0.5,-0.5, 1.0}, {0.0, 1.0, 0.0, 1.0}},
        {{ 0.5, 0.5,-0.5, 1.0}, {0.0, 1.0, 0.0, 1.0}},
        {{-0.5, 0.5,-0.5, 1.0}, {0.0, 1.0, 0.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 1.0, 0.0, 1.0}},

        // Bottom face
        {{-0.5,-0.5,-0.5, 1.0}, {0.0,-1.0, 0.0, 1.0}},
        {{ 0.5,-0.5,-0.5, 1.0}, {0.0,-1.0, 0.0, 1.0}},
        {{ 0.5,-0.5, 0.5, 1.0}, {0.0,-1.0, 0.0, 1.0}},
        {{ 0.5,-0.5, 0.5, 1.0}, {0.0,-1.0, 0.0, 1.0}},
        {{-0.5,-0.5, 0.5, 1.0}, {0.0,-1.0, 0.0, 1.0}},
        {{-0.5,-0.5,-0.5, 1.0}, {0.0,-1.0, 0.0, 1.0}},

        // Left face
        {{-0.5,-0.5,-0.5, 1.0}, {-1.0,0.0, 0.0, 1.0}},
        {{-0.5,-0.5, 0.5, 1.0}, {-1.0,0.0, 0.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {-1.0,0.0, 0.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {-1.0,0.0, 0.0, 1.0}},
        {{-0.5, 0.5,-0.5, 1.0}, {-1.0,0.0, 0.0, 1.0}},
        {{-0.5,-0.5,-0.5, 1.0}, {-1.0,0.0, 0.0, 1.0}},

        // Right face
        {{ 0.5,-0.5, 0.5, 1.0}, {1.0, 0.0, 0.0, 1.0}},
        {{ 0.5,-0.5,-0.5, 1.0}, {1.0, 0.0, 0.0, 1.0}},
        {{ 0.5, 0.5,-0.5, 1.0}, {1.0, 0.0, 0.0, 1.0}},
        {{ 0.5, 0.5,-0.5, 1.0}, {1.0, 0.0, 0.0, 1.0}},
        {{ 0.5, 0.5, 0.5, 1.0}, {1.0, 0.0, 0.0, 1.0}},
        {{ 0.5,-0.5, 0.5, 1.0}, {1.0, 0.0, 0.0, 1.0}},
    };
    
    lightVertexBuffer = metalDevice->newBuffer(&lightSource, sizeof(lightSource), MTL::ResourceStorageModeShared);
}

void MTLEngine::createBuffers() {
    
}

void MTLEngine::createDefaultLibrary() {
    // Create an NSString from the metallib path
    NS::String* libraryPath = NS::String::string(
        SHADER_METALLIB,
        NS::UTF8StringEncoding
    );
    
    NS::Error* error = nullptr;
    
    metalDefaultLibrary = metalDevice->newLibrary(libraryPath, &error);
    
    if (!metalDefaultLibrary) {
        std::cerr << "Failed to load metal library at path: " << SHADER_METALLIB;
        if (error) {
            std::cerr << "\nError: " << error->localizedDescription()->utf8String();
        }
        std::exit(-1);
    }
}

void MTLEngine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void MTLEngine::createRenderPipeline() {
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

void MTLEngine::createLightSourceRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("lightVertexShader", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("lightFragmentShader", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    assert(renderPipelineDescriptor);
    MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
    renderPipelineDescriptor->setSampleCount(4);
    renderPipelineDescriptor->setLabel(NS::String::string("Light Source Render Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    renderPipelineDescriptor->setTessellationOutputWindingOrder(MTL::WindingClockwise);
    
    NS::Error* error;
    metalLightSourceRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MTLEngine::createDepthAndMSAATextures() {
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

void MTLEngine::createRenderPassDescriptor() {
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

void MTLEngine::updateRenderPassDescriptor() {
    renderPassDescriptor->colorAttachments()->object(0)->setTexture(msaaRenderTargetTexture);
    renderPassDescriptor->colorAttachments()->object(0)->setResolveTexture(metalDrawable->texture());
    renderPassDescriptor->depthAttachment()->setTexture(depthTexture);
}


void MTLEngine::draw() {
    sendRenderCommand();
}

void MTLEngine::sendRenderCommand() {
    metalCommandBuffer = metalCommandQueue->commandBuffer();

    updateRenderPassDescriptor();
    MTL::RenderCommandEncoder* renderCommandEncoder = metalCommandBuffer->renderCommandEncoder(renderPassDescriptor);
    encodeRenderCommand(renderCommandEncoder);
    renderCommandEncoder->endEncoding();

    metalCommandBuffer->presentDrawable(metalDrawable);
    metalCommandBuffer->commit();
    metalCommandBuffer->waitUntilCompleted();
}

void MTLEngine::encodeRenderCommand(MTL::RenderCommandEncoder* renderCommandEncoder) {
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
	renderCommandEncoder->setCullMode(MTL::CullModeBack);

//    renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines);
    renderCommandEncoder->setRenderPipelineState(metalRenderPSO);
    renderCommandEncoder->setDepthStencilState(depthStencilState);
    renderCommandEncoder->setVertexBuffer(mesh->vertexBuffer, 0, 0);

    // Aspect ratio should match the ratio between the window width and height,
    // otherwise the image will look stretched.
    float aspectRatio = metalDrawable->layer()->drawableSize().width / 
                        metalDrawable->layer()->drawableSize().height;

    matrix_float4x4 viewMatrix = camera.getViewMatrix();
    matrix_float4x4 projectionMatrix = camera.getProjectionMatrix(aspectRatio);
    
    // Update your model-view-projection matrices
    matrix_float4x4 rotationMatrix = matrix4x4_rotation(90 * (M_PI / 180.0f), 1.0, 0.0, 0.0);
	matrix_float4x4 modelMatrix = matrix4x4_translation(0.0f, 0.0f, 0.0f);// * rotationMatrix;
    
    // Send matrices to shaders
    renderCommandEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), 1);
    renderCommandEncoder->setVertexBytes(&viewMatrix, sizeof(viewMatrix), 2);
    renderCommandEncoder->setVertexBytes(&projectionMatrix, sizeof(projectionMatrix), 3);

    // Set up the light source
    simd_float4 lightColor = simd_make_float4(1.0, 1.0, 1.0, 1.0);
    renderCommandEncoder->setFragmentBytes(&lightColor, sizeof(lightColor), 1);
    simd_float4 lightPosition = simd_make_float4(2 * cos(glfwGetTime()), 6.0, -0.5, 1);
    renderCommandEncoder->setFragmentBytes(&lightPosition, sizeof(lightPosition), 2);
    renderCommandEncoder->setFragmentTexture(mesh->diffuseTextures, 3);
	renderCommandEncoder->setFragmentTexture(mesh->normalTextures, 4);
    renderCommandEncoder->setFragmentBuffer(mesh->diffuseTextureInfos, 0, 5);
	renderCommandEncoder->setFragmentBuffer(mesh->normalTextureInfos, 0, 6);
    
    // Tell the input assembler to draw triangles
    MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
    renderCommandEncoder->drawIndexedPrimitives(typeTriangle, mesh->indexCount, MTL::IndexTypeUInt32, mesh->indexBuffer, 0);

//	// Light Shader
    matrix_float4x4 scaleMatrix = matrix4x4_scale(0.3f, 0.3f, 0.3f);
    matrix_float4x4 translationMatrix = matrix4x4_translation(lightPosition.xyz);
    
    modelMatrix = matrix_identity_float4x4;
    modelMatrix = matrix_multiply(scaleMatrix, modelMatrix);
    modelMatrix = matrix_multiply(translationMatrix, modelMatrix);
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);

    renderCommandEncoder->setRenderPipelineState(metalLightSourceRenderPSO);
    renderCommandEncoder->setVertexBuffer(lightVertexBuffer, 0, 0);
    renderCommandEncoder->setVertexBytes(&modelMatrix, sizeof(modelMatrix), 1);
    renderCommandEncoder->setVertexBytes(&viewMatrix, sizeof(viewMatrix), 2);
    renderCommandEncoder->setVertexBytes(&projectionMatrix, sizeof(projectionMatrix), 3);
    typeTriangle = MTL::PrimitiveTypeTriangle;
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = 6 * 6;
    renderCommandEncoder->setFragmentBytes(&lightColor, sizeof(lightColor), 0);
    renderCommandEncoder->drawPrimitives(typeTriangle, vertexStart, vertexCount);
}
