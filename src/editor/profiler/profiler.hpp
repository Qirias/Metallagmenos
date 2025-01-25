#pragma once

#include "pch.hpp"

#include <Metal/Metal.hpp>
#include <GLFW/glfw3.h>
#include "../../external/imgui/imgui.h"

class Profiler {
public:
    enum class Type {
        CPU,
        GPU
    };

    struct StageTimingInfo {
        std::string name;
        Type type;
        double startTime;
    };

    static void initialize(MTL::Device* device);

    static void startStageTimer(MTL::Device* device,
                                const std::string& stageName, 
                                Type type = Type::GPU, 
                                MTL::CommandBuffer* commandBuffer = nullptr);

    static void stopStageTimer(MTL::Device* device,
                               const std::string& stageName, 
                               Type type = Type::GPU, 
                               MTL::CommandBuffer* commandBuffer = nullptr);

    static std::vector<std::pair<std::string, double>> getProfileData();
    static void reset();
    static void debugPrintState();
    static void cleanup();

    static std::vector<std::pair<std::string, double>> getAndResetFrameData();
    static void trackFrameHistory(std::deque<std::vector<std::pair<std::string, double>>>& profilerDataHistory);

private:
    static std::unordered_map<std::string, StageTimingInfo> activeTimers;
    static std::vector<std::pair<std::string, double>> stageDurations;

    MTL::CounterSampleBuffer* m_counterSampleBuffer;

    // CPU and GPU start timestamps for baseline
    static double m_cpuStartTimestamp;
    static double m_gpuStartTimestamp;
};