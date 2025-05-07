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
	std::vector<MTL::Buffer*> 		            frameDataBuffers;
    std::vector<std::vector<MTL::Buffer*>>      cascadeDataBuffer; // Per cascade data buffer. First dimension is the frame index from frames in flight
    std::vector<std::vector<MTL::Buffer*>>      probeAccumBuffer;

    MTL::Device*        metalDevice;
    GLFWwindow*         glfwWindow;
    NSWindow*           metalWindow;
    CAMetalLayer*       metalLayer;
    CA::MetalDrawable*  metalDrawable;

    // Managers
    RenderPipeline                      renderPipelines;
    std::unique_ptr<Debug>              debug;
    std::unique_ptr<Editor>             editor;
    std::unique_ptr<ResourceManager>    resourceManager;
    std::unique_ptr<RayTracingManager>  rayTracingManager;
    std::unique_ptr<RenderPassManager>  renderPassManager;
    
    bool                windowResizeFlag = false;
    int                 newWidth;
    int                 newHeight;

    Camera              camera;
    simd::float3        lastFrameCameraPosition = simd::float3{0, 0, 0};
    simd::float3        lastFrameCameraForward = simd::float3{0, 0, 1};
    float               lastFrame;
    
    static void mouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
    static void cursorPosCallback(GLFWwindow* window, double xpos, double ypos);

    // Renderpass descriptors
	MTL::RenderPassDescriptor* 	viewRenderPassDescriptor;
    MTL::RenderPassDescriptor*  depthPrepassDescriptor;
    MTL::RenderPassDescriptor*  finalGatherDescriptor;
	
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
    
    // Forward Debug
    MTL::RenderPassDescriptor*              forwardDescriptor;
    // Buffer that stores world space positions of the debug probes
    std::vector<std::vector<MTL::Buffer*>>  probePosBuffer;
    // Buffer that stores ray directions of the debug probes
    std::vector<std::vector<MTL::Buffer*>>  rayBuffer;
    int                                     debugProbeCount = 0; // Don't adjust this value, it is set in the engine.mm
    int                                     rayCount = 0; // Same here
    int                                     debugCascadeLevel = 3; // This is the level of cascade that you will be debugging
    
    // Debugging probes and rays
    void createSphereGrid();
    void createDebugLines();
};
