#include "debug.hpp"

Debug::Debug(MTL::Device* device) : metalDevice(device) {}

Debug::~Debug() {
    clean();
}

void Debug::clean() {
    if (lineBuffer) {
        lineBuffer->release();
        lineBuffer = nullptr;
    }

    if (lineCountBuffer) {
        lineCountBuffer->release();
        lineCountBuffer = nullptr;
    }

    metalDevice = nullptr;
}

void Debug::allocateBuffers(size_t additionalLines) {
    size_t requiredLines = currentLineCount + additionalLines;

    if (requiredLines > maxLineCount) {
        maxLineCount = requiredLines;
        size_t newBufferSize = maxLineCount * 2 * sizeof(DebugLineVertex);

        MTL::Buffer* newBuffer = metalDevice->newBuffer(newBufferSize, MTL::ResourceStorageModeShared);
        newBuffer->setLabel(NS::String::string("Line Buffer", NS::ASCIIStringEncoding));

        if (lineBuffer) {
            // Copy existing line data into the new buffer
            memcpy(newBuffer->contents(), lineBuffer->contents(), currentLineCount * 2 * sizeof(DebugLineVertex));
            lineBuffer->release();
        }
        lineBuffer = newBuffer;

        if (lineCountBuffer) {
            lineCountBuffer->release();
        }
        lineCountBuffer = metalDevice->newBuffer(sizeof(uint32_t), MTL::ResourceStorageModeShared);
        lineCountBuffer->setLabel(NS::String::string("Line Count Buffer", NS::ASCIIStringEncoding));
    }
}


// https://github.com/krupitskas/Yasno/blob/0e14e793807aa0115543a572ad95485b86ac6647/shaders/include/debug_renderer.hlsl#L63
void Debug::addSphereLines(const simd::float3& center, float radius, const simd::float3& color, int slices, int stacks, DebugLineVertex* lineVertices, size_t& lineIndex) {
    for (int i = 0; i < stacks; ++i) {
        float theta1 = (i / (float)stacks) * M_PI;
        float theta2 = ((i + 1) / (float)stacks) * M_PI;

        for (int j = 0; j < slices; ++j) {
            float phi1 = (j / (float)slices) * 2.0f * M_PI;
            float phi2 = ((j + 1) / (float)slices) * 2.0f * M_PI;

            float3 p1 = center + radius * float3{sin(theta1) * cos(phi1), cos(theta1), sin(theta1) * sin(phi1)};
            float3 p2 = center + radius * float3{sin(theta2) * cos(phi1), cos(theta2), sin(theta2) * sin(phi1)};
            float3 p3 = center + radius * float3{sin(theta2) * cos(phi2), cos(theta2), sin(theta2) * sin(phi2)};
            float3 p4 = center + radius * float3{sin(theta1) * cos(phi2), cos(theta1), sin(theta1) * sin(phi2)};

            lineVertices[lineIndex * 2 + 0].position = {p1.x, p1.y, p1.z, 1.0f};
            lineVertices[lineIndex * 2 + 0].color = {color.x, color.y, color.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].position = {p2.x, p2.y, p2.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].color = {color.x, color.y, color.z, 1.0f};
            ++lineIndex;

            lineVertices[lineIndex * 2 + 0].position = {p2.x, p2.y, p2.z, 1.0f};
            lineVertices[lineIndex * 2 + 0].color = {color.x, color.y, color.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].position = {p3.x, p3.y, p3.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].color = {color.x, color.y, color.z, 1.0f};
            ++lineIndex;

            lineVertices[lineIndex * 2 + 0].position = {p3.x, p3.y, p3.z, 1.0f};
            lineVertices[lineIndex * 2 + 0].color = {color.x, color.y, color.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].position = {p4.x, p4.y, p4.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].color = {color.x, color.y, color.z, 1.0f};
            ++lineIndex;

            lineVertices[lineIndex * 2 + 0].position = {p4.x, p4.y, p4.z, 1.0f};
            lineVertices[lineIndex * 2 + 0].color = {color.x, color.y, color.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].position = {p1.x, p1.y, p1.z, 1.0f};
            lineVertices[lineIndex * 2 + 1].color = {color.x, color.y, color.z, 1.0f};
            ++lineIndex;
        }
    }
}

void Debug::drawSpheres(const std::vector<simd::float3>& spherePositions, float radius, const simd::float3& color) {
    int slices = 8;
    int stack = 8;
    size_t additionalLines = spherePositions.size() * slices * stack * 4;
    allocateBuffers(additionalLines);

    DebugLineVertex* lineVertices = reinterpret_cast<DebugLineVertex*>(lineBuffer->contents());
    uint32_t* lineCount = reinterpret_cast<uint32_t*>(lineCountBuffer->contents());

    size_t lineIndex = currentLineCount;
    for (const auto& position : spherePositions) {
        addSphereLines(position, radius, color, slices, stack, lineVertices, lineIndex);
    }

    currentLineCount = lineIndex;
    *lineCount = static_cast<uint32_t>(currentLineCount);
}

void Debug::addLine(const simd::float3& start, const simd::float3& end, const simd::float3& color, DebugLineVertex* lineVertices, size_t& lineIndex) {
    lineVertices[lineIndex * 2 + 0].position = {start.x, start.y, start.z, 1.0f};
    lineVertices[lineIndex * 2 + 0].color = {color.x, color.y, color.z, 1.0f};
    lineVertices[lineIndex * 2 + 1].position = {end.x, end.y, end.z, 1.0f};
    lineVertices[lineIndex * 2 + 1].color = {color.x, color.y, color.z, 1.0f};
    ++lineIndex;
}

void Debug::drawLines(const std::vector<simd::float3>& startPoints, const std::vector<simd::float3>& endPoints, const simd::float3& color) {
    if (startPoints.size() != endPoints.size()) {
        throw std::invalid_argument("Start points and end points must have the same size.");
    }

    size_t additionalLines = startPoints.size();
    allocateBuffers(additionalLines);

    DebugLineVertex* lineVertices = reinterpret_cast<DebugLineVertex*>(lineBuffer->contents());
    uint32_t* lineCount = reinterpret_cast<uint32_t*>(lineCountBuffer->contents());

    size_t lineIndex = currentLineCount;
    for (size_t i = 0; i < startPoints.size(); ++i) {
        addLine(startPoints[i], endPoints[i], color, lineVertices, lineIndex);
    }

    currentLineCount = lineIndex;
    *lineCount = static_cast<uint32_t>(currentLineCount);
}
