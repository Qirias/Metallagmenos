#pragma once

#include "pch.hpp"

#define GLFW_INCLUDE_NONE
#import <glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#import <glfw3native.h>

#include <Metal/Metal.hpp>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.hpp>
#include <QuartzCore/CAMetalLayer.h>
#include <QuartzCore/QuartzCore.hpp>

// #include "AAPLMathUtilities.h"

#include "vertexData.hpp"
#include "texture.hpp"
#include "Components/mesh.hpp"
#include "Components/textureArray.hpp"
#include "Components/camera.hpp"

#include <stb/stb_image.h>

#include <simd/simd.h>
#include <filesystem>

class MTLEngine {
public:
    void init();
    void run();
    void cleanup();

    MTLEngine() : camera(simd::float3{0.0f, 0.0f, 3.0f}), lastFrame(0.0f) {}

private:
    void initDevice();
    void initWindow();

    void loadMeshes();
    void createBuffers();

    void createDepthAndMSAATextures();
    void createRenderPassDescriptor();

    // resizing window
    void updateRenderPassDescriptor();

    void createDefaultLibrary();
    void createCommandQueue();
    void createRenderPipeline();
    void createLightSourceRenderPipeline();

    void encodeRenderCommand(MTL::RenderCommandEncoder* renderEncoder);
    void sendRenderCommand();
    void draw();

    static void frameBufferSizeCallback(GLFWwindow *window, int width, int height);
    void resizeFrameBuffer(int width, int height);

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
    MTL::CommandBuffer*         metalCommandBuffer;
    MTL::RenderPipelineState*   metalRenderPSO;

    Mesh*                       mesh;
    MTL::RenderPipelineState*   metalLightSourceRenderPSO;
    MTL::Buffer*                lightVertexBuffer;
    MTL::Buffer*                lightTransformationBuffer;

    Texture*                    grassTexture;
};
