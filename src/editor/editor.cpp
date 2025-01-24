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
    Cleanup();
}

void Editor::BeginFrame(MTL::RenderPassDescriptor* passDescriptor) {
    ImGui_ImplMetal_NewFrame(passDescriptor);
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

//    createDockSpace();
}

void Editor::EndFrame(MTL::CommandBuffer* commandBuffer, MTL::RenderCommandEncoder* encoder) {
    ImGui::Begin("Debug Window", nullptr, ImGuiWindowFlags_None);
    
    static bool enableDebugFeature = false;
    ImGui::Checkbox("Enable Debug Mode", &enableDebugFeature);
    
    if (enableDebugFeature) {
        ImGui::Text("Debug mode is active");
    }
    
    ImGui::End();
    
    drawProfilerWindow();
    
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

void Editor::Cleanup() {
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}

void Editor::drawProfilerWindow() {
    ImGui::Begin("Profiler");
    
    // Initialize average durations
    std::vector<std::pair<std::string, double>> averageDurations;
    std::unordered_map<std::string, size_t> stageIndexMap;
    
    // Calculate averages (identical to your existing implementation)
    for (const auto& frameData : profilerDataHistory) {
        for (size_t i = 0; i < frameData.size(); ++i) {
            const auto& [stage, duration] = frameData[i];
            if (stageIndexMap.find(stage) == stageIndexMap.end()) {
                stageIndexMap[stage] = averageDurations.size();
                averageDurations.emplace_back(stage, 0.0);
            }
            averageDurations[stageIndexMap[stage]].second += duration;
        }
    }
    
    // Calculate the average
    for (auto& [stage, totalDuration] : averageDurations) {
        totalDuration /= historySize;
    }

    if (averageDurations.empty()) {
            ImGui::Text("No profiling data available.");
            ImGui::End();
            return;
        }

        // Calculate total frame time by summing all average durations
        float totalTime = 0.0f;
        for (const auto& [stage, duration] : averageDurations) {
            totalTime += static_cast<float>(duration);
        }

        const float bar_height = 10.0f;
        const float spacing = 2.0f;
        const float text_width = 150.0f;
        const float duration_text_width = 70.0f;
        const float bar_start_x = text_width + spacing;
        const float bar_width = ImGui::GetContentRegionAvail().x - bar_start_x - duration_text_width - spacing;

        float startTime = 0.0f;

        size_t i = 0;
        for (const auto& [stageName, duration] : averageDurations) {

            ImVec4 stageColor = getColorForIndex(i++, averageDurations.size());
            ImGui::PushStyleColor(ImGuiCol_Text, stageColor);

            // Display stage name
            ImGui::Text("%s", stageName.c_str());
            ImGui::SameLine(bar_start_x);

            // Draw stage bar
            ImDrawList* draw_list = ImGui::GetWindowDrawList();
            ImVec2 cursor_pos = ImGui::GetCursorScreenPos();

            draw_list->AddRectFilled(
                ImVec2(cursor_pos.x + bar_width * (startTime / totalTime), cursor_pos.y),
                ImVec2(cursor_pos.x + bar_width * ((startTime + duration) / totalTime), cursor_pos.y + bar_height),
                ImColor(stageColor)
            );

            ImGui::Dummy(ImVec2(bar_width, bar_height));  // Reserve space for the bar
            ImGui::SameLine();

            // Display duration text
            char duration_text[32];
            snprintf(duration_text, sizeof(duration_text), "%.2f ms", static_cast<float>(duration));
            ImGui::Text("%s", duration_text);
            ImGui::PopStyleColor();

            // Distribute everything evenly inside the window
            ImGui::Spacing();

            // Update start time for the next stage
            startTime += static_cast<float>(duration);
        }

    // Display total frame time
    ImGui::Text("Total Time: %.2f ms", totalTime);
    ImGui::End();
}

ImVec4 Editor::getColorForIndex(int index, int total) {
    // Generate a unique color for each bar
    float hue = index / float(total);
    return ImColor::HSV(hue, 0.7f, 0.9f);
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
