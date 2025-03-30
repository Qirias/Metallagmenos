#include "editor.hpp"
#include "../../external/imgui/backends/imgui_impl_metal.h"
#include "../../external/imgui/backends/imgui_impl_glfw.h"

Editor::Editor(GLFWwindow* window, MTL::Device* device)
: window(window), device(device) {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;

    ImGui_ImplGlfw_InitForOther(window, true);
    
    ImGui_ImplMetal_Init(device);
}

Editor::~Editor() {
    cleanup();
}

void Editor::beginFrame(MTL::RenderPassDescriptor* passDescriptor) {
    ImGui_ImplMetal_NewFrame(passDescriptor);
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

//    createDockSpace();
    debugWindow();
}

void Editor::endFrame(MTL::CommandBuffer* commandBuffer, MTL::RenderCommandEncoder* encoder) {
    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);

    ImGuiIO& io = ImGui::GetIO();
    // If true it crushes in xcode when dragging a window outside of metal view.
    // It doesn't crush in standalone though...
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}
void Editor::cleanup() {
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}

void Editor::debugWindow() {
    ImGui::Begin("Debug Window", nullptr, ImGuiWindowFlags_None);
    
    // Set the font scale to make everything smaller
    ImGui::SetWindowFontScale(0.8f);
    
    // Make the window more compact by reducing item spacing and padding
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4, 2));
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(2, 1));
    
    // Make all input widgets half width
    float halfWidth = ImGui::GetContentRegionAvail().x * 0.5f;
    ImGui::PushItemWidth(halfWidth);

    ImGui::Checkbox("Enable Debug Mode", &debug.enableDebugFeature);
    
    ImGui::InputFloat("Interval Length", &debug.intervalLength, 0.1f, 1.0f, "%.2f");
    
    ImGui::SliderInt("Cascade Level", &debug.debugCascadeLevel, -1, 5);
    
    // Create a collapsible header for Camera Position (closed by default)
    if (ImGui::CollapsingHeader("Camera Position", !ImGuiTreeNodeFlags_DefaultOpen)) {
        float camX = debug.cameraPosition.x;
        float camY = debug.cameraPosition.y;
        float camZ = debug.cameraPosition.z;

        // Quarter width for camera inputs (even smaller)
        float quarterWidth = ImGui::GetContentRegionAvail().x * 0.25f;
        ImGui::PushItemWidth(quarterWidth);
        
        // Stack the X, Y, Z inputs vertically
        if (ImGui::InputFloat("X##CamPos", &camX, 0.1f, 1.0f, "%.3f")) {
            debug.cameraPosition.x = camX;
        }
        
        if (ImGui::InputFloat("Y##CamPos", &camY, 0.1f, 1.0f, "%.3f")) {
            debug.cameraPosition.y = camY;
        }
        
        if (ImGui::InputFloat("Z##CamPos", &camZ, 0.1f, 1.0f, "%.3f")) {
            debug.cameraPosition.z = camZ;
        }
        
        ImGui::PopItemWidth(); // Pop camera position item width
    }
    
    // Restore original settings
    ImGui::PopItemWidth(); // Pop general item width
    ImGui::PopStyleVar(2); // Pop both style vars
    
    ImGui::End();
}
void Editor::createDockSpace() {
    static bool dockspaceOpen = true;
    static bool opt_fullscreen = true;
    static bool opt_padding = false;
    static ImGuiDockNodeFlags dockspace_flags = ImGuiDockNodeFlags_None;

    ImGuiWindowFlags window_flags = ImGuiWindowFlags_MenuBar | ImGuiWindowFlags_NoDocking;
    if (opt_fullscreen) {
        const ImGuiViewport* viewport = ImGui::GetMainViewport();
        ImGui::SetNextWindowPos(viewport->WorkPos);
        ImGui::SetNextWindowSize(viewport->WorkSize);
        ImGui::SetNextWindowViewport(viewport->ID);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
        window_flags |= ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove;
        window_flags |= ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoNavFocus;
    } else {
        dockspace_flags &= ~ImGuiDockNodeFlags_PassthruCentralNode;
    }

    if (dockspace_flags & ImGuiDockNodeFlags_PassthruCentralNode)
        window_flags |= ImGuiWindowFlags_NoBackground;

    if (!opt_padding)
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
    ImGui::Begin("DockSpace Demo", &dockspaceOpen, window_flags);
    if (!opt_padding)
        ImGui::PopStyleVar();

    if (opt_fullscreen)
        ImGui::PopStyleVar(2);

    ImGuiIO& io = ImGui::GetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_DockingEnable) {
        ImGuiID dockspace_id = ImGui::GetID("MyDockSpace");
        ImGui::DockSpace(dockspace_id, ImVec2(0.0f, 0.0f), dockspace_flags);
    }

    ImGui::End();
}
