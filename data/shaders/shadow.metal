#include "shaderTypes.hpp"
#include "vertexData.hpp"

struct ShadowOutput
{
    float4 position [[position]];
};

vertex ShadowOutput shadow_vertex(const device Vertex*		positions 	[[buffer(0)]],
                                  constant     FrameData&	frameData 	[[buffer(2)]],
                                  uint                      vertexID 	[[vertex_id]])
{
    ShadowOutput out;

    // Add vertex pos to fairy position and project to clip-space
    out.position = frameData.shadow_mvp_matrix * positions[vertexID].position;

    return out;
}
