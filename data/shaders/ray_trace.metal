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

//float2 octEncode(float3 n) {
//    n /= (abs(n.x) + abs(n.y) + abs(n.z));
//    n.xy = (n.z >= 0.0) ? n.xy : (1.0 - abs(n.yx)) * sign(n.xy);
//    return n.xy * 0.5 + 0.5;
//}

//float3 octDecode(float2 f) {
//    f = f * 2.0 - 1.0;
//    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
//    float t = max(-n.z, 0.0);
//    n.xy -= sign(n.xy) * t;
//    return normalize(n);
//}

kernel void raytracingKernel(texture2d<float, access::write>    radianceTexture         [[texture(TextureIndexRadiance)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                    constant CascadeData&                       cascadeData             [[buffer(BufferIndexCascadeData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
                      device ProbeRay*                          rayData                 [[buffer(BufferIndexProbeRayData)]],
                             texture2d<float, access::sample>   minMaxTexture           [[texture(TextureIndexMinMaxDepth)]],
                             uint                               tid                     [[thread_position_in_grid]]) {
    const uint probeSpacing = cascadeData.probeSpacing;
    uint cascadeLevel = cascadeData.cascadeLevel;
    
    uint tileSize = probeSpacing * (1 << cascadeLevel);
    uint probeGridSizeX = (frameData.framebuffer_width + tileSize - 1) / tileSize;
    uint probeGridSizeY = (frameData.framebuffer_height + tileSize - 1) / tileSize;
    uint numRays = 8 * (1 << (2 * cascadeLevel));
    uint totalProbes = probeGridSizeX * probeGridSizeY;
    uint totalThreads = totalProbes * numRays;

    if (tid >= totalThreads) {
        return;
    }

    uint rayIndex = tid % numRays;
    uint probeIndex = tid / numRays;
    uint probeIndexY = probeIndex / probeGridSizeX;
    uint probeIndexX = probeIndex % probeGridSizeX;

    float2 uv = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 ndc = uv * 2.0f - 1.0f;
    ndc.y = -ndc.y;
    float2 minMaxDepth = minMaxTexture.sample(depthSampler, uv).xy;
    float probeDepth = minMaxDepth.y;
    float3 worldPos = reconstructWorldPosition(ndc, probeDepth,
                                               frameData.projection_matrix_inverse,
                                               frameData.inverse_view_matrix);

    if (rayIndex == 0) {
        probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    }

    uint probeDim = cascadeLevel == 0 ? 4 : uint(ceil(sqrt(float(numRays))));
    
    if (cascadeLevel == 5) probeDim = 64;
    else if (cascadeLevel == 6) probeDim = 182;

    uint raysPerDim = probeDim;
    uint octX, octY;
    if (cascadeLevel == 0) {
        uint gridIndices[8] = {0, 3, 5, 6, 9, 10, 12, 15};
        uint gridIndex = gridIndices[rayIndex];
        octX = gridIndex % raysPerDim;
        octY = gridIndex / raysPerDim;
    } else {
        octX = rayIndex % raysPerDim;
        octY = rayIndex / raysPerDim;
    }
    float2 octUV = (float2(octX, octY) + 0.5f) / float(raysPerDim);
    float3 rayDir = octDecode(octUV);

    float shortestSide = min(float(frameData.framebuffer_width), float(frameData.framebuffer_height));

    float intervalStart = (cascadeData.cascadeLevel == 0) ? 0.0 : pow(8.0f, float(cascadeData.cascadeLevel-1)) / shortestSide;
    float intervalEnd = pow(8.0f, float(cascadeData.cascadeLevel+1)) / shortestSide;

    ray ray;
    ray.origin = worldPos;
    ray.direction = rayDir;
    ray.min_distance = intervalStart;
    ray.max_distance = intervalEnd;

    intersector<triangle_data> intersector;
    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);

    float3 startPoint = worldPos + rayDir * intervalStart;
    float3 endPoint = worldPos + rayDir * intervalEnd;

    uint rayDataIndex = probeIndex * numRays + rayIndex;
    rayData[rayDataIndex].intervalStart = float4(startPoint, 1.0);
    rayData[rayDataIndex].intervalEnd = float4(endPoint, 1.0);

    float4 radiance;
    if (result.type != intersection_type::none) {
        unsigned int primitiveIndex = result.primitive_id;
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];
        if (triangle.colors[0].a == -1.0f) {
            radiance = float4(/*triangle.colors[0].rgb*/1.0,0.0,0.0, 1.0); // Emissive irradiance
        } else {
            radiance = float4(0.8, 0.8, 0.8, 1.0); // Non-emissive hit, no contribution
//            radiance = float4(float(rayIndex) / float(numRays - 1), 0.5, 1.0, 1.0);
        }
    } else {
        radiance = float4(0.8, 0.8, 0.8, 1.0); // No hit, default to black (or sky color)
    }
    
    rayData[rayDataIndex].color = radiance;

    uint texX = probeIndexX * probeDim + (rayIndex % probeDim);
    uint texY = probeIndexY * probeDim + (rayIndex / probeDim);
    
    radianceTexture.write(radiance, uint2(texX, texY));
}
