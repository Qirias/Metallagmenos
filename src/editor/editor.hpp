#pragma once

#include "pch.hpp"

#include <Metal/Metal.hpp>
#include <GLFW/glfw3.h>
#include "../../external/imgui/imgui.h"
#include "profiler/profiler.hpp"

class Editor {
public:
    Editor(GLFWwindow* window, MTL::Device* device);
    ~Editor();

    void BeginFrame(MTL::RenderPassDescriptor* passDescriptor);
    void EndFrame(MTL::CommandBuffer* commandBuffer, MTL::RenderCommandEncoder* encoder);
    void Cleanup();
private:
    GLFWwindow* window;
    MTL::Device* device;

    void createDockSpace();
    
    std::deque<std::vector<std::pair<std::string, double>>> profilerDataHistory;
    std::vector<std::pair<std::string, double>> currentFrameStages;
    static const size_t historySize = 30; // Number of frames to average over
    
    void drawProfilerWindow();
    ImVec4 getColorForIndex(int index, int total);
};
