#pragma once

#include "pch.hpp"

#include <Metal/Metal.hpp>
#include <GLFW/glfw3.h>
#include "../../external/imgui/imgui.h"
#include "../core/vertexData.hpp"

class Debug {
public:
    Debug(MTL::Device* device);
    ~Debug();
    
    void drawSpheres(const std::vector<simd::float4>& spherePositions, float radius, simd::float3& color);
    void drawLines(const std::vector<simd::float4>& startPoints, const std::vector<simd::float4>& endPoints, const std::vector<simd::float4>& color);
    void clearLines();

    MTL::Buffer* lineBuffer = nullptr;
    MTL::Buffer* lineCountBuffer = nullptr;

private:
    void allocateBuffers(size_t maxLines);
    void addSphereLines(const simd::float3& center, float radius, const simd::float3& color, int slices, int stacks, DebugLineVertex* lineVertices, size_t& lineIndex);
    void addLine(const simd::float4& start, const simd::float4& end, const simd::float4& color, DebugLineVertex* lineVertices, size_t& lineIndex);

    void clean();

    MTL::Device* metalDevice;
    size_t maxLineCount = 0;
    size_t currentLineCount = 0;
};
