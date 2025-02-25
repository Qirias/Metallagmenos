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

float3 octDecode(float2 f) {
    f = f * 2.0 - 1.0;
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    float t = -max(-n.z, 0.0);
    n.xy += sign(n.xy) * t;
    return normalize(n);
}

//float3 octDecode(float2 f) {
//    f = f * 2.0 - 1.0;
//    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
//    float t = max(-n.z, 0.0);
//    n.xy -= sign(n.xy) * t;
//    return normalize(n);
//}

kernel void raytracingKernel(texture2d<float, access::write>    rayTracingTexture       [[texture(TextureIndexRaytracing)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
                      device ProbeRay*                          rayData                 [[buffer(BufferIndexProbeRayData)]],
                             texture2d<float, access::sample>   minMaxTexture           [[texture(TextureIndexMinMaxDepth)]],
                             texture2d<float, access::read>     directionTexture        [[texture(TextureIndexDirectionEncoding)]],
                             uint                               tid                     [[thread_position_in_grid]]) {
    
    uint probeSpacing = 2;
    uint probeGridSizeX = (frameData.framebuffer_width + (probeSpacing * (1 << frameData.cascadeLevel)) - 1) / (probeSpacing * (1 << frameData.cascadeLevel));
    uint probeGridSizeY = (frameData.framebuffer_height + (probeSpacing * (1 << frameData.cascadeLevel)) - 1) / (probeSpacing * (1 << frameData.cascadeLevel));
    uint numRays = 8 * (1 << (2 * frameData.cascadeLevel));
    uint totalProbes = probeGridSizeX * probeGridSizeY;
    uint totalThreads = totalProbes * numRays;
       
    if (tid >= totalThreads)
        return;
   
    uint rayIndex = tid % numRays;
    uint probeIndex = tid / numRays;
    uint probeIndexY = probeIndex / probeGridSizeX;
    uint probeIndexX = probeIndex % probeGridSizeX;

    float2 uv = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 ndc = uv * 2.0f - 1.0f;
    ndc.y = -ndc.y;  // Flip Y for correct NDC

    float2 minMaxDepth = minMaxTexture.sample(depthSampler, uv, level(frameData.cascadeLevel)).xy;
    float probeDepth = minMaxDepth.x;

    float3 worldPos = reconstructWorldPosition(ndc, probeDepth,
                                            frameData.projection_matrix_inverse,
                                            frameData.inverse_view_matrix);

    // Store probe position if it's the first ray
    if (rayIndex == 0) {
        probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    }

    // Define ray tracing interval based on cascade level
    float shortestSide = min(frameData.framebuffer_width, frameData.framebuffer_height);
    float baseLength = pow(2.0f, float(frameData.cascadeLevel)) / shortestSide;
    float intervalStart = baseLength;
    float intervalEnd = baseLength * 8.0f;

    uint textureWidth = directionTexture.get_width();
//    uint textureHeight = directionTexture.get_height();

    // Calculate linear index for this ray
    uint linearIndex = (probeIndexY * probeGridSizeX + probeIndexX) * numRays + rayIndex;

    // Map to 2D texture coordinates
    uint texX = linearIndex % textureWidth;
    uint texY = linearIndex / textureWidth;

    float4 encodedDirection = directionTexture.read(uint2(texX, texY));
    float2 encoded = encodedDirection.xy;
    float3 rayDir = octDecode(encoded);

    ray ray;
    ray.origin = worldPos;
    ray.direction = rayDir;
    ray.min_distance = intervalStart;
    ray.max_distance = intervalEnd;

    intersector<triangle_data> intersector;
    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);

    // Compute interval start and end points
    float3 startPoint = worldPos + rayDir * intervalStart;
    float3 endPoint = worldPos + rayDir * intervalEnd;

    // Store interval data
    rayData[probeIndex * numRays + rayIndex].intervalStart = float4(startPoint, 1.0);
    rayData[probeIndex * numRays + rayIndex].intervalEnd = float4(endPoint, 1.0);

    if (result.type != intersection_type::none) {
        unsigned int primitiveIndex = result.primitive_id;
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];

        if (triangle.colors[0].a == -1.0f)
            rayData[probeIndex * numRays + rayIndex].color = float4(1.0, 0.0, 0.0, 1.0);
        else
            rayData[probeIndex * numRays + rayIndex].color = float4(0.5f, 0.5f, 1.0f, 1.0);
    }
    else
        rayData[probeIndex * numRays + rayIndex].color = float4(0.5f, 0.5f, 1.0f, 1.0);
}
