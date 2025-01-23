#pragma once

#include <Metal/Metal.hpp>
#include <GLFW/glfw3.h>
#include "../../external/imgui/imgui.h"

class Editor {
public:
    Editor(GLFWwindow* window, MTL::Device* device);
    ~Editor();

    void BeginFrame(MTL::RenderPassDescriptor* passDescriptor);
    void EndFrame(MTL::CommandBuffer* commandBuffer);
    void Cleanup();

private:
    GLFWwindow* window;
};
