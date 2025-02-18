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

float2 octEncode(float3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = (n.z >= 0.0) ? n.xy : (1.0 - abs(n.yx)) * sign(n.xy);
    return n.xy * 0.5 + 0.5;
}

float3 octDecode(float2 f) {
    f = f * 2.0 - 1.0;
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    float t = -max(-n.z, 0.0);
    n.xy += sign(n.xy) * t;
    return normalize(n);
}

float3 getRayDirection(int rayIndex, int level) {
    int hrings = 4 << level;
    int vrings = 4 << level;
    
    // Convert rayIndex to ring positions
    float a0 = rayIndex / vrings;
    float a1 = rayIndex % vrings;
    
    // Add 0.5 to center within each subdivision
    float angle0 = 2.0 * M_PI_F * (a0 + 0.5) / float(hrings);
    float angle1 = 2.0 * M_PI_F * (a1 + 0.5) / float(vrings);
    
    // Convert spherical coordinates to Cartesian
    float sinAngle0 = sin(angle0);
    float cosAngle0 = cos(angle0);
    float sinAngle1 = sin(angle1);
    float cosAngle1 = cos(angle1);
    
    return normalize(float3(
        sinAngle0 * cosAngle1,
        sinAngle0 * sinAngle1,
        cosAngle0
    ));
}

kernel void raytracingKernel(texture2d<float, access::write>    rayTracingTexture       [[texture(TextureIndexRaytracing)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
                      device ProbeRay*                          rayData                 [[buffer(BufferIndexProbeRayData)]],
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
    float probeDepth = minMaxDepth.x;
    
    float3 worldPos = reconstructWorldPosition(ndc, probeDepth,
                                            frameData.projection_matrix_inverse,
                                            frameData.inverse_view_matrix);
    
    probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    
    float shortestSide = min(frameData.framebuffer_width, frameData.framebuffer_height);
        
    float baseLength = pow(2.0f, float(frameData.cascadeLevel)) / shortestSide;
    float intervalStart = baseLength;
    float intervalEnd = baseLength * 16.0f;

    int numRays = 8 * (1 << (2 * frameData.cascadeLevel));

    for (int i = 0; i < numRays; ++i) {
        float3 rayDir = getRayDirection(i, frameData.cascadeLevel);
        
        ray ray;
        ray.origin = worldPos;
        ray.direction = rayDir;
        ray.min_distance = intervalStart;
        ray.max_distance = intervalEnd;
        
        intersector<triangle_data> intersector;
//        intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);
        
        float3 startPoint = worldPos + rayDir * intervalStart;
        float3 endPoint = worldPos + rayDir * intervalEnd;
        
        rayData[probeIndex * numRays + i].intervalStart = float4(startPoint, 1.0);
        rayData[probeIndex * numRays + i].intervalEnd = float4(endPoint, 1.0);
    }

    rayTracingTexture.write(float4(probeDepth, probeDepth, probeDepth, 1.0), tid);
}
