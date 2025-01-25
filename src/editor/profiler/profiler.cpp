#include "profiler.hpp"

std::unordered_map<std::string, Profiler::StageTimingInfo> Profiler::activeTimers;
std::vector<std::pair<std::string, double>> Profiler::stageDurations;
double Profiler::m_cpuStartTimestamp = 0;
double Profiler::m_gpuStartTimestamp = 0;

void Profiler::initialize(MTL::Device* device) {
    MTL::Timestamp gpuTime, cpuTime;
    device->sampleTimestamps(&gpuTime, &cpuTime);
    m_cpuStartTimestamp = cpuTime;
    m_gpuStartTimestamp = gpuTime;

    MTL::CounterSampleBufferDescriptor* descriptor = MTL::CounterSampleBufferDescriptor::alloc()->init();
    descriptor->setSampleCount(8);
}

void Profiler::startStageTimer(MTL::Device* device,
                               const std::string& stageName, 
                               Type type, 
                               MTL::CommandBuffer* commandBuffer) {
    StageTimingInfo info;
    info.name = stageName;
    info.type = type;

    if (type == Type::GPU) {
        // Associate the command buffer with the timer
        activeTimers[stageName] = info;
    } else {
        // For CPU, sample the timestamp directly
        MTL::Timestamp gpuTime, cpuTime;
        device->sampleTimestamps(&gpuTime, &cpuTime);
        info.startTime = cpuTime;
        activeTimers[stageName] = info;
    }
}

void Profiler::stopStageTimer(MTL::Device* device,
                              const std::string& stageName, 
                              Type type, 
                              MTL::CommandBuffer* commandBuffer) {
    auto it = activeTimers.find(stageName);
    if (it == activeTimers.end()) {
        std::cerr << "No active timer for: " << stageName << std::endl;
        return;
    }

    if (type == Type::GPU) {
        // Add a completed handler to the command buffer
        commandBuffer->addCompletedHandler([stageName](MTL::CommandBuffer* completedBuffer) {
            MTL::Timestamp gpuTime, cpuTime;
            completedBuffer->device()->sampleTimestamps(&gpuTime, &cpuTime);

            auto it = activeTimers.find(stageName);
            if (it != activeTimers.end()) {
                double duration = gpuTime - it->second.startTime;
                stageDurations.emplace_back(stageName, duration / 1000000.0);
                activeTimers.erase(it);
            }
        });
    } else {
        // For CPU, sample the timestamp directly
        MTL::Timestamp gpuTime, cpuTime;
        device->sampleTimestamps(&gpuTime, &cpuTime);

        double endTime = cpuTime;
        double duration = endTime - it->second.startTime;

        stageDurations.emplace_back(stageName, duration / 1000000.0);
        activeTimers.erase(it);
    }
}

std::vector<std::pair<std::string, double>> Profiler::getProfileData() {
    return stageDurations;
}

void Profiler::reset() {
    activeTimers.clear();
    stageDurations.clear();
}

std::vector<std::pair<std::string, double>> Profiler::getAndResetFrameData() {
    std::vector<std::pair<std::string, double>> currentFrameData(stageDurations);
    stageDurations.clear();
    return currentFrameData;
}

void Profiler::trackFrameHistory(std::deque<std::vector<std::pair<std::string, double>>>& profilerDataHistory) {
    if (!stageDurations.empty()) {
        // If history is full, remove oldest entry
        if (profilerDataHistory.size() >= 30) {
            profilerDataHistory.pop_front();
        }
        
        // Add current frame's data
        profilerDataHistory.push_back(stageDurations);
    }
}

void Profiler::debugPrintState() {
    std::cout << "Active Timers: " << activeTimers.size() << std::endl;
    std::cout << "Completed Stages: " << stageDurations.size() << std::endl;

    for (const auto& stage : stageDurations) {
        std::cout << stage.first << ": " << stage.second << " ms" << std::endl;
    }
}

void Profiler::cleanup() {
    reset();
}