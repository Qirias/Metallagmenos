#include "imguiManager.hpp"
#include "../../external/imgui/backends/imgui_impl_metal.h"
#include "../../external/imgui/backends/imgui_impl_glfw.h"

ImGuiManager::ImGuiManager(GLFWwindow* window, MTL::Device* device)
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

ImGuiManager::~ImGuiManager() {
    Cleanup();
}

void ImGuiManager::BeginFrame(MTL::RenderPassDescriptor* passDescriptor) {
    ImGui_ImplMetal_NewFrame(passDescriptor);
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();
}

void ImGuiManager::EndFrame(MTL::CommandBuffer* commandBuffer) {
    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, nullptr);

    ImGuiIO& io = ImGui::GetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}

void ImGuiManager::Cleanup() {
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}