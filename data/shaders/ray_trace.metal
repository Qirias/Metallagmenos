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

//float3 octDecode(float2 f) {
//    f = f * 2.0 - 1.0;
//    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
//    float t = -max(-n.z, 0.0);
//    n.xy += sign(n.xy) * t;
//    return normalize(n);
//}

float2 octEncode(float3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = (n.z >= 0.0) ? n.xy : (1.0 - abs(n.yx)) * sign(n.xy);
    return n.xy * 0.5 + 0.5;
}

float3 octDecode(float2 f) {
    f = f * 2.0 - 1.0;
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    float t = max(-n.z, 0.0);
    n.xy -= sign(n.xy) * t;
    return normalize(n);
}

float4 mergeUpperCascade(texture2d<float, access::sample> upperRadianceTexture,
                         uint cascadeLevel,
                         float2 probeUV,
                         float3 rayDir,
                         uint tileSize,
                         CascadeData cascadeData) {
    if (cascadeLevel >= 5) return float4(0.0);
    
    uint upperTileSize = cascadeData.probeSpacing * (1 << (cascadeLevel + 1));
    float2 upperProbeUV = probeUV * 2.0;
    float2 upperOctUV = octEncode(rayDir);
    float2 sampleUV = upperProbeUV + (upperOctUV * (float(tileSize) / float(upperTileSize))); // Scale to upper tile

    return upperRadianceTexture.sample(samplerLinear, sampleUV);
}

kernel void raytracingKernel(texture2d<float, access::write>    radianceTexture         [[texture(TextureIndexRadiance)]],
                             texture2d<float, access::sample>   upperRadianceTexture    [[texture(TextureIndexRadianceUpper)]],
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

    // Map probe to screen UV (center of probe’s tile)
    float2 probeUV = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 probeNDC = probeUV * 2.0f - 1.0f;
    probeNDC.y = -probeNDC.y;
    float2 minMaxDepth = minMaxTexture.sample(depthSampler, probeUV).xy;
    float probeDepth = minMaxDepth.y;
    float3 worldPos = reconstructWorldPosition(probeNDC, probeDepth,
                                               frameData.projection_matrix_inverse,
                                               frameData.inverse_view_matrix);

    if (rayIndex == 0) {
        probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    }

    // Map ray within probe’s tile (tileSize × tileSize pixels)
    uint raysPerDim = cascadeLevel == 0 ? 4 : uint(sqrt(float(numRays)));
    int rayX;
    int rayY;
    if (cascadeLevel == 0) {
        uint gridIndices[8] = {0, 3, 5, 6, 9, 10, 12, 15};
        uint gridIndex = gridIndices[rayIndex];
        rayX = gridIndex % raysPerDim;
        rayY = gridIndex / raysPerDim;
    } else {
        rayX = rayIndex % raysPerDim;
        rayY = rayIndex / raysPerDim;
    }
    
    float2 rayUV = (float2(rayX, rayY) + 0.5f) / float(raysPerDim); // 0–1 within tile
    float2 tileUV = probeUV + (rayUV - 0.5f) * (float(tileSize) / float(frameData.framebuffer_width)); // Scale to screen UV
    float2 rayNDC = tileUV * 2.0f - 1.0f;
    rayNDC.y = -rayNDC.y;

    float3 rayDir = octDecode(rayUV);

    float shortestSide = min(float(frameData.framebuffer_width), float(frameData.framebuffer_height));
    float intervalStart = (cascadeLevel == 0) ? 0.0 : pow(8.0f, float(cascadeLevel - 1)) / shortestSide;
    float intervalEnd = 4.0f * pow(8.0f, float(cascadeLevel + 1)) / shortestSide;

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
        radiance = (triangle.colors[0].a == -1.0f) ? float4(triangle.colors[0].rgb, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
    } else {
        radiance = float4(0.0, 0.0, 0.0, 1.0);
    }

    // Merge with upper cascade
    float4 mergedRadiance = radiance;
    if (cascadeLevel < 5) {
        float4 upperRadiance = mergeUpperCascade(upperRadianceTexture, cascadeLevel, probeUV, rayDir, tileSize, cascadeData);
        mergedRadiance.rgb += upperRadiance.rgb * mergedRadiance.a;
        mergedRadiance.a *= upperRadiance.a;
    }

    rayData[rayDataIndex].color = radiance;

    uint texX = uint(tileUV.x * frameData.framebuffer_width);
    uint texY = uint(tileUV.y * frameData.framebuffer_height);
    radianceTexture.write(radiance, uint2(texX, texY));
}
