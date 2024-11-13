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

#include <stb/stb_image.h>

#include <simd/simd.h>
#include <filesystem>

constexpr uint8_t MaxFramesInFlight = 3;

class Engine {
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
	void endFrame(MTL::CommandBuffer* commandBuffer, MTL::Drawable* currentDrawable);
    void updateWorldState(bool isPaused);
	
	void drawShadow(MTL::CommandBuffer* commandBuffer);

    void createDepthAndMSAATextures();
    void createRenderPassDescriptor();

    // resizing window
    void updateRenderPassDescriptor();

    void createDefaultLibrary();
    void createCommandQueue();
    void createRenderPipeline();
    void createLightSourceRenderPipeline();

    void encodeRenderCommand(MTL::RenderCommandEncoder* renderCommandEncoder);
    void sendRenderCommand();
    void draw();
    void drawScene(MTL::RenderCommandEncoder* renderCommandEncoder);

    static void frameBufferSizeCallback(GLFWwindow *window, int width, int height);
    void resizeFrameBuffer(int width, int height);
	
	dispatch_semaphore_t                                inFlightSemaphore;
    std::array<dispatch_semaphore_t, MaxFramesInFlight> frameSemaphores;
    uint8_t                                             currentFrameIndex;
	
	// Buffers used to store dynamically changing per-frame data
	MTL::Buffer* frameDataBuffers[MaxFramesInFlight];

    MTL::Device*        metalDevice;
    GLFWwindow*         glfwWindow;
    NSWindow*           metalWindow;
    CAMetalLayer*       metalLayer;
    CA::MetalDrawable*  metalDrawable;
    
    bool                windowResizeFlag = false;
    int                 newWidth;
    int                 newHeight;

    Camera              camera;
    float               lastFrame;
    
    static void mouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
    static void cursorPosCallback(GLFWwindow* window, double xpos, double ypos);

    MTL::DepthStencilState*     depthStencilState;
    MTL::RenderPassDescriptor*  renderPassDescriptor;
    MTL::Texture*               msaaRenderTargetTexture = nullptr;
    MTL::Texture*               depthTexture;
    int                         sampleCount = 4;

    MTL::Library*               metalDefaultLibrary;
    MTL::CommandQueue*          metalCommandQueue;
    // MTL::CommandBuffer*         metalCommandBuffer;
    MTL::RenderPipelineState*   metalRenderPSO;

    Mesh*                       mesh;
    MTL::RenderPipelineState*   metalLightSourceRenderPSO;
    MTL::Buffer*                lightVertexBuffer;
    MTL::Buffer*                lightTransformationBuffer;

    MTL::SamplerState*          samplerState;

    uint64_t                    frameNumber;
    uint8_t                     frameDataBufferIndex;
	float 						sunAzimuth;
	float 						sunAltitude;

    // remove these when you set up the frameData buffer
    simd_float4                 sunDirection;
};
