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

#include "vertexData.hpp"
#include "texture.hpp"
#include <stb/stb_image.h>

#include <simd/simd.h>
#include <filesystem>

class MTLEngine {
public:
    void init();
    void run();
    void cleanup();

private:
    void initDevice();
    void initWindow();

    void createSquare();
    void createDefaultLibrary();
    void createCommandQueue();
    void createRenderPipeline();

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

    MTL::Library*               metalDefaultLibrary;
    MTL::CommandQueue*          metalCommandQueue;
    MTL::CommandBuffer*         metalCommandBuffer;
    MTL::RenderPipelineState*   metalRenderPSO;
    MTL::Buffer*                squareVertexBuffer;

    Texture*                    grassTexture;
};
