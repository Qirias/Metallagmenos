#pragma once

#include "pch.hpp"

#define GLFW_INCLUDE_NONE
#import <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#import <GLFW/glfw3native.h>

#include <Metal/Metal.hpp>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.hpp>
#include <QuartzCore/CAMetalLayer.h>
#include <QuartzCore/QuartzCore.hpp>

// #include "AAPLMathUtilities.h"

#include "vertexData.hpp"
#include "texture.hpp"
#include "components/mesh.hpp"
#include "components/textureArray.hpp"
#include "components/camera.hpp"
#include "components/gltfLoader.hpp"
#include "../../data/shaders/shaderTypes.hpp"
#include "../../data/shaders/config.hpp"
#include "managers/renderPipeline.hpp"
#include "../editor/editor.hpp"
#include "../debug/debug.hpp"

#include <stb/stb_image.h>

#include <simd/simd.h>
#include <filesystem>

constexpr uint8_t MaxFramesInFlight = 3;

class Engine {
    struct TriangleData {
        simd::float4 normals[3];
        simd::float4 colors[3];
    };
public:
    void init();
    void run();
    void cleanup();

	Engine();

private:
    void initDevice();
    void initWindow();

    void loadScene();
    void createBuffers();
	
	MTL::CommandBuffer* beginFrame(bool isPaused);
	MTL::CommandBuffer* beginDrawableCommands();
	void endFrame(MTL::CommandBuffer* commandBuffer, MTL::Drawable* currentDrawable);
    void updateWorldState(bool isPaused);
	
	void draw();
	void drawMeshes(MTL::RenderCommandEncoder* renderCommandEncoder);
	void drawGBuffer(MTL::RenderCommandEncoder* renderCommandEncoder);
	void drawDirectionalLight(MTL::RenderCommandEncoder* renderCommandEncoder);

    void createDepthTexture();
	void createViewRenderPassDescriptor();

    // resizing window
    void updateRenderPassDescriptor();

    void createDefaultLibrary();
    void createCommandQueue();
    void createRenderPipelines();
    void createLightSourceRenderPipeline();

    void encodeRenderCommand(MTL::RenderCommandEncoder* renderCommandEncoder);
    void sendRenderCommand();


    static void frameBufferSizeCallback(GLFWwindow *window, int width, int height);
    void resizeFrameBuffer(int width, int height);
	
	dispatch_semaphore_t                                inFlightSemaphore;
    std::array<dispatch_semaphore_t, MaxFramesInFlight> frameSemaphores;
    uint8_t                                             currentFrameIndex;
	
	// Buffers used to store dynamically changing per-frame data
	MTL::Buffer* 		frameDataBuffers[MaxFramesInFlight];

    MTL::Device*        metalDevice;
    GLFWwindow*         glfwWindow;
    NSWindow*           metalWindow;
    CAMetalLayer*       metalLayer;
    CA::MetalDrawable*  metalDrawable;

    // Managers
    RenderPipeline                renderPipelines;
    std::unique_ptr<Editor>       editor;
    
    bool                windowResizeFlag = false;
    int                 newWidth;
    int                 newHeight;

    Camera              camera;
    float               lastFrame;
    
    static void mouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
    static void cursorPosCallback(GLFWwindow* window, double xpos, double ypos);

    // Renderpass descriptors
	MTL::RenderPassDescriptor* 	viewRenderPassDescriptor;
	
	// GBuffer properties
	MTL::PixelFormat 			albedoSpecularGBufferFormat;
	MTL::PixelFormat 			normalMapGBufferFormat;
	MTL::PixelFormat 			depthGBufferFormat;
	MTL::Texture* 				albedoSpecularGBuffer;
	MTL::Texture* 				normalMapGBuffer;
	MTL::Texture* 				depthGBuffer;

	MTL::StorageMode 			GBufferStorageMode;

	MTL::Texture* 				depthStencilTexture;

	MTL::VertexDescriptor*		defaultVertexDescriptor;
    MTL::Library*               metalDefaultLibrary;
    MTL::CommandQueue*          metalCommandQueue;
	
    std::vector<Mesh*>          meshes;

    MTL::SamplerState*          samplerState;

    uint64_t                    frameNumber;
    uint8_t                     frameDataBufferIndex;
    
    // Ray tracing
    std::vector<MTL::AccelerationStructure*>    primitiveAccelerationStructures;
    MTL::Buffer*                                resourceBuffer;
    size_t                                      totalTriangles;
    MTL::Texture*                               rayTracingTexture;
    
    void setupTriangleResources();
    void createAccelerationStructureWithDescriptors();
    void dispatchRaytracing(MTL::CommandBuffer* commandBuffer);
    
    // Forward Debug
    std::unique_ptr<Debug> debug;
    MTL::RenderPassDescriptor*  forwardDescriptor;
    MTL::Texture*               forwardDepthStencilTexture;
    
    void createSphereGrid();
    void createDebugLines();
    void drawDebug(MTL::RenderCommandEncoder* commandEncoder, MTL::CommandBuffer* commandBuffer);
};
