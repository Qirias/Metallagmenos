#define METAL
#include <metal_stdlib>
using namespace metal;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

struct DepthPrepassOut {
    float4 position [[position]];
    float3 eye_position;
};

constant bool hasTextures [[function_constant(0)]];

struct DescriptorDefinedVertex
{
    float4  position    [[attribute(VertexAttributePosition)]];
    half4   normal      [[attribute(VertexAttributeNormal)]];
    float2  tex_coord   [[attribute(VertexAttributeTexcoord), function_constant(hasTextures)]];
    half4   tangent     [[attribute(VertexAttributeTangent), function_constant(hasTextures)]];
    half4   bitangent   [[attribute(VertexAttributeBitangent), function_constant(hasTextures)]];
};

float linear_Depth(float depth, float near, float far) {
    float z = depth * 2.0f - 1.0f;
    return (2.0f * near * far) / (far + near - z * (far - near));
}

vertex DepthPrepassOut depth_prepass_vertex(DescriptorDefinedVertex in          [[stage_in]],
                                   constant FrameData&              frameData   [[buffer(BufferIndexFrameData)]],
                                   constant float4x4&               modelMatrix [[buffer(BufferIndexVertexBytes)]]) {
    DepthPrepassOut out;
    
    float4 model_position = modelMatrix * in.position;
    float4 eye_position = frameData.scene_modelview_matrix * model_position;
    
    out.position = frameData.projection_matrix * eye_position;
    out.eye_position = eye_position.xyz;
    
    return out;
}

fragment float4 depth_prepass_fragment(DepthPrepassOut      in          [[stage_in]],
                             constant  FrameData&           frameData   [[buffer(BufferIndexFrameData)]]) {    
    float depth = in.position.z;
    float linearValue = linear_Depth(depth, frameData.near_plane, frameData.far_plane);
    
    return float4(linearValue, 0.0, 0.0, 1.0);
}
