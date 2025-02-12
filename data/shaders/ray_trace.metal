#define METAL
#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

struct TriangleResources {
    struct TriangleData {
        float4 normals[3];
        float4 colors[3];
    };
    device TriangleData* triangles;
};

float3 reconstructWorldPosition(float2 ndc, float depth,
                                simd::float4x4 projectionMatrixInverse,
                                simd::float4x4 viewMatrixInverse) {
    float4 clipPos  = float4(ndc, depth, 1.0f);
    float4 viewPos  = projectionMatrixInverse * clipPos;
    viewPos         = viewPos / viewPos.w;
    float4 worldPos = viewMatrixInverse * viewPos;
    
    return worldPos.xyz;
}

kernel void raytracingKernel(texture2d<float, access::write>    rayTracingTexture       [[texture(TextureIndexRaytracing)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
                             texture2d<float, access::sample>   minMaxTexture           [[texture(TextureIndexMinMaxDepth)]],
                             uint2                              tid                     [[thread_position_in_grid]]) {
    
    int tile_size = 8 * 1 << frameData.cascadeLevel;
    uint2 probeGridSize = uint2(frameData.framebuffer_width / tile_size, frameData.framebuffer_height / tile_size);

    if (tid.x >= probeGridSize.x || tid.y >= probeGridSize.y) {
        return;
    }

    float2 uv = (float2(tid) + 0.5f) / float2(probeGridSize);
    float2 ndc = uv * 2.0f - 1.0f;
    ndc.y = -ndc.y;
    
    uint probeIndex = tid.y * probeGridSize.x + tid.x;

    float2 minMaxDepth = minMaxTexture.sample(depthSampler, uv, level(frameData.cascadeLevel)).xy;
    float probeDepth = minMaxDepth.y;
    
    float3 worldPos = reconstructWorldPosition(ndc, probeDepth,
                                            frameData.projection_matrix_inverse,
                                            frameData.inverse_view_matrix);
    
    probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    
    rayTracingTexture.write(float4(probeDepth, probeDepth, probeDepth, 1.0), tid);
}
