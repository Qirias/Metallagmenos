#pragma once

#include <Metal/Metal.hpp>
#include <GLFW/glfw3.h>
#include "../../external/imgui/imgui.h"

class ImGuiManager {
public:
    ImGuiManager(GLFWwindow* window, MTL::Device* device);
    ~ImGuiManager();

    void BeginFrame(MTL::RenderPassDescriptor* passDescriptor);
    void EndFrame(MTL::CommandBuffer* commandBuffer);
    void Cleanup();

private:
    GLFWwindow* window;
};
