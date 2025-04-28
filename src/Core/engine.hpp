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


#include "vertexData.hpp"
#include "components/mesh.hpp"
#include "components/camera.hpp"
#include "components/gltfLoader.hpp"
#include "components/sceneParser.hpp"
#include "../../data/shaders/config.hpp"
#include "managers/renderPipeline.hpp"
#include "../editor/editor.hpp"
#include "../debug/debug.hpp"
#include "managers/resourceManager.hpp"
#include "managers/renderPassManager.hpp"
#include "managers/rayTracingManager.hpp"

#include <stb/stb_image.h>

#include <simd/simd.h>
#include <filesystem>

constexpr uint8_t MaxFramesInFlight = 1;
constexpr float NEAR_PLANE = 0.1f;
constexpr float FAR_PLANE = 100.0f;


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

    void loadSceneFromJSON(const std::string& jsonFilePath);
    void loadScene();
    void createBuffers();
	
	MTL::CommandBuffer* beginFrame(bool isPaused);
	MTL::CommandBuffer* beginDrawableCommands();
	void endFrame(MTL::CommandBuffer* commandBuffer);
    void updateWorldState(bool isPaused);
	
	void draw();

	void createViewRenderPassDescriptor();

    // resizing window
    void updateRenderPassDescriptor();

    MTL::VertexDescriptor* createDefaultVertexDescriptor();
    void createDefaultLibrary();
    void createCommandQueue();
    void createRenderPipelines();

    void encodeRenderCommand(MTL::RenderCommandEncoder* renderCommandEncoder);
    void sendRenderCommand();

    static void frameBufferSizeCallback(GLFWwindow *window, int width, int height);
    void resizeFrameBuffer(int width, int height);
	
	dispatch_semaphore_t                                inFlightSemaphore;
    std::array<dispatch_semaphore_t, MaxFramesInFlight> frameSemaphores;
    uint                                                currentFrameIndex;
	
	// Buffers used to store dynamically changing per-frame data
	MTL::Buffer* 		frameDataBuffers[MaxFramesInFlight];

    MTL::Device*        metalDevice;
    GLFWwindow*         glfwWindow;
    NSWindow*           metalWindow;
    CAMetalLayer*       metalLayer;
    CA::MetalDrawable*  metalDrawable;

    // Managers
    RenderPipeline                      renderPipelines;
    std::unique_ptr<Editor>             editor;
    std::unique_ptr<ResourceManager>    resourceManager;
    std::unique_ptr<RayTracingManager>  rayTracingManager;
    std::unique_ptr<RenderPassManager>  renderPassManager;
    
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

	MTL::StorageMode 			GBufferStorageMode;

	MTL::VertexDescriptor*		defaultVertexDescriptor;
    MTL::Library*               metalDefaultLibrary;
    MTL::CommandQueue*          metalCommandQueue;
	
    std::vector<Mesh*>          meshes;

    MTL::SamplerState*          samplerState;

    uint64_t                    frameNumber;
    uint8_t                     frameDataBufferIndex;
    
    // Ray tracing
    std::vector<MTL::AccelerationStructure*>    primitiveAccelerationStructures;
    std::vector<std::vector<MTL::Buffer*>>      cascadeDataBuffer;
    MTL::RenderPassDescriptor*                  finalGatherDescriptor;
    
    
    // Forward Debug
    std::unique_ptr<Debug>                  debug;
    MTL::RenderPassDescriptor*              forwardDescriptor;
    std::vector<std::vector<MTL::Buffer*>>  probePosBuffer;
    std::vector<std::vector<MTL::Buffer*>>  rayBuffer;
    int                                     debugProbeCount = 0;
    int                                     rayCount = 0;
    int                                     debugCascadeLevel = 0;
    bool                                    createDebugData = false;
    
    void createSphereGrid();
    void createDebugLines();

    MTL::RenderPassDescriptor*  depthPrepassDescriptor;
};
