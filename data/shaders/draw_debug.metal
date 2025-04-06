#define METAL
#include <metal_stdlib>
using namespace metal;

#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

struct DebugLineVertex {
    float4 position [[position]];
    float4 color;
};

vertex DebugLineVertex forwardVertex(uint                vertexID        [[vertex_id]],
                         constant    DebugLineVertex*    lineVertices    [[buffer(0)]],
                         constant    FrameData&          frameData       [[buffer(BufferIndexFrameData)]]) {
    DebugLineVertex outVertex = lineVertices[vertexID];
    outVertex.position = frameData.projection_matrix * frameData.view_matrix * outVertex.position;

    return outVertex;
}

fragment float4 forwardFragment(DebugLineVertex in [[stage_in]]) {
    return in.color;
}
