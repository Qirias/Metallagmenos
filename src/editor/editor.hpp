#pragma once

#include "pch.hpp"

#include <Metal/Metal.hpp>
#include <GLFW/glfw3.h>
#include "../../external/imgui/imgui.h"

class Editor {
public:
    Editor(GLFWwindow* window, MTL::Device* device);
    ~Editor();

    void beginFrame(MTL::RenderPassDescriptor* passDescriptor);
    void endFrame(MTL::CommandBuffer* commandBuffer, MTL::RenderCommandEncoder* encoder);
    void cleanup();
    
private:
    GLFWwindow* window;
    MTL::Device* device;

    void createDockSpace();
};
