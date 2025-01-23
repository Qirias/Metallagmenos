#include "editor.hpp"
#include "../../external/imgui/backends/imgui_impl_metal.h"
#include "../../external/imgui/backends/imgui_impl_glfw.h"

Editor::Editor(GLFWwindow* window, MTL::Device* device)
    : window(window) {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;

    ImGui_ImplGlfw_InitForOther(window, true);
    
    ImGui_ImplMetal_Init(device);
}

Editor::~Editor() {
    Cleanup();
}

void Editor::BeginFrame(MTL::RenderPassDescriptor* passDescriptor) {
    ImGui_ImplMetal_NewFrame(passDescriptor);
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();
}

void Editor::EndFrame(MTL::CommandBuffer* commandBuffer) {
    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, nullptr);

    ImGuiIO& io = ImGui::GetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}

void Editor::Cleanup() {
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}