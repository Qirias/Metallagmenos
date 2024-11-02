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


class MTLEngine {
public:
    void init();
    void run();
    void cleanup();

private:
    void initDevice();
    void initWindow();

    MTL::Device*    metalDevice;
    GLFWwindow*     glfwWindow;
    NSWindow*       metalWindow;
    CAMetalLayer*   metalLayer;
};
