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

float2 signNotZero(float2 v) {
    return float2((v.x >= 0.0) ? +1.0 : -1.0, (v.y >= 0.0) ? +1.0 : -1.0);
}

//float2 octEncode(float3 n) {
//    float2 p = n.xy * (1.0 / (abs(n.x) + abs(n.y) + abs(n.z)));
//    return (n.z <= 0.0) ? ((1.0 - abs(p.yx)) * signNotZero(p)) : p;
//}
//
//float3 octDecode(float2 f) {
//    f = f * 2.0 - 1.0;
//    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
//    if (n.z < 0)
//        n.xy = (1.0f - abs(n.yz)) * signNotZero(n.xy);
//    return normalize(n);
//}

float2 octEncode(float3 n) {
    float l1norm = abs(n.x) + abs(n.y) + abs(n.z);
    float2 p = n.xy * (1.0 / l1norm);
    p = (n.z <= 0.0) ? ((1.0 - abs(p.yx)) * signNotZero(p)) : p;
    return p * 0.5 + 0.5; // -1,1 to 0,1
}

float3 octDecode(float2 f) {
    f = f * 2.0 - 1.0; // 0,1 to -1,1
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    if (n.z < 0)
        n.xy = (1.0 - abs(n.yx)) * signNotZero(n.xy);
    return normalize(n);
}

float4 sampleProbeRadiance(texture2d<float, access::sample> radianceTexture,
                          float2 probeCoord,
                          float3 direction,
                          uint gridSizeX,
                          uint gridSizeY,
                          uint tileSize,
                          float2 frameSize) {
    // Center of probe
    float2 probeUV = (probeCoord + 0.5f) / float2(gridSizeX, gridSizeY);
    
    float2 octCoords = octEncode(direction);
    float2 tileUVSize = float2(tileSize) / frameSize;
    float2 sampleUV = probeUV + (octCoords - 0.5f) * tileUVSize;
    
    return radianceTexture.sample(samplerLinear, sampleUV);
}

float4 interpolateProbeGrid(texture2d<float, access::sample> radianceTexture,
                           float2 positionUV,
                           float3 direction,
                           uint gridSizeX,
                           uint gridSizeY,
                           uint tileSize,
                           float2 frameSize) {
    // Convert position UV to grid coordinates (with fractional part)
    float2 gridCoord = positionUV * float2(gridSizeX, gridSizeY) - 0.5f;
    
    // Get the four surrounding probe indices with proper clamping
    int2 probeMin = int2(floor(gridCoord));
    int2 probeMax = probeMin + int2(1);
    
    probeMin = max(probeMin, int2(0));
    probeMax = min(probeMax, int2(gridSizeX - 1, gridSizeY - 1));
    
    float2 t = fract(gridCoord);
    
    int2 probes[4] = {
        int2(probeMin.x, probeMin.y),  // Bottom-left
        int2(probeMax.x, probeMin.y),  // Bottom-right
        int2(probeMin.x, probeMax.y),  // Top-left
        int2(probeMax.x, probeMax.y)   // Top-right
    };
    
    float4 weights = float4(
        (1.0 - t.x) * (1.0 - t.y),  // Bottom-left
        t.x * (1.0 - t.y),          // Bottom-right
        (1.0 - t.x) * t.y,          // Top-left
        t.x * t.y                   // Top-right
    );
    
    float4 result = float4(0.0);
    float weightSum = 0.0;
    
    for (int i = 0; i < 4; i++) {
        // Sample from this probe
        float4 probeSample = sampleProbeRadiance(
            radianceTexture,
            float2(probes[i]),
            direction,
            gridSizeX,
            gridSizeY,
            tileSize,
            frameSize
        );
        
        // Add weighted contribution if the probe has valid radiance
        if (/*probeSample.a > 0.0*/true) {
            result += weights[i] * probeSample;
            weightSum += weights[i];
        }
    }
    
    // Normalize by weight sum to handle edge cases
    return (weightSum > 0.0) ? result / weightSum : float4(0.0);
}

float4 mergeUpperCascade(texture2d<float, access::sample> upperRadianceTexture,
                        float2 worldPosUV,
                        float3 rayDir,
                        uint tileSize,
                        CascadeData cascadeData,
                        FrameData frameData) {
    if (cascadeData.cascadeLevel >= 5) return float4(0.0);
    
    uint upperCascadeLevel = cascadeData.cascadeLevel + 1;
    uint upperTileSize = cascadeData.probeSpacing * (1 << upperCascadeLevel);
    
    // Calculate probe grid dimensions for upper cascade
    uint upperGridSizeX = (frameData.framebuffer_width + upperTileSize - 1) / upperTileSize;
    uint upperGridSizeY = (frameData.framebuffer_height + upperTileSize - 1) / upperTileSize;
    
    float4 upperRadiance = interpolateProbeGrid(
        upperRadianceTexture,
        worldPosUV,
        rayDir,
        upperGridSizeX,
        upperGridSizeY,
        upperTileSize,
        float2(frameData.framebuffer_width, frameData.framebuffer_height)
    );
    
    return upperRadiance;
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

    // Map probe to screen UV (center of probe's tile)
    float2 probeUV = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 probeNDC = probeUV * 2.0f - 1.0f;
    probeNDC.y = -probeNDC.y;
    float2 minMaxDepth = minMaxTexture.sample(depthSampler, probeUV).xy;
    float probeDepth = (minMaxDepth.x + minMaxDepth.y) * 0.5f;
    float3 worldPos = reconstructWorldPosition(probeNDC, probeDepth,
                                               frameData.projection_matrix_inverse,
                                               frameData.inverse_view_matrix);

    if (rayIndex == 0) {
        probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    }

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
    float2 tileUV = probeUV + (rayUV - 0.5f) * (float(tileSize) / float(frameData.framebuffer_width));
//    float2 rayNDC = tileUV * 2.0f - 1.0f;
//    rayNDC.y = -rayNDC.y;

    float3 rayDir = octDecode(rayUV);

    float shortestSide = min(float(frameData.framebuffer_width), float(frameData.framebuffer_height));
    float intervalStart = (cascadeLevel == 0) ? 0.0 : pow(8.0f, float(cascadeLevel - 1)) / shortestSide;
    float intervalEnd = pow(8.0f, float(cascadeLevel + 1)) / shortestSide;

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
    
    // Direct radiance from current cascade
    float4 radiance = float4(0.0);
    if (result.type != intersection_type::none) {
        unsigned int primitiveIndex = result.primitive_id;
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];
        radiance = (triangle.colors[0].a == -1.0f) ? float4(triangle.colors[0].rgb, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
    } else {
        radiance = float4(0.0, 0.0, 0.0, 1.0);
    }
    
    float2 worldPosUV = float2((probeNDC.x + 1.0) * 0.5, (1.0 - probeNDC.y) * 0.5);
    
    // Get radiance from upper cascade
    float4 upperRadiance = float4(0.0);
    if (cascadeLevel < 5) {
        upperRadiance = mergeUpperCascade(
            upperRadianceTexture,
            worldPosUV,
            rayDir,
            tileSize,
            cascadeData,
            frameData
        );
    }
        
    if (result.type == intersection_type::none) {
        // If no hit in current cascade, fully use upper cascade
        radiance = upperRadiance;
    } else {
        radiance.rgb += upperRadiance.rgb * radiance.a;
        radiance.a *= upperRadiance.a;
    }
    
    rayData[rayDataIndex].color = radiance;
    
    uint texX = uint(tileUV.x * frameData.framebuffer_width);
    uint texY = uint(tileUV.y * frameData.framebuffer_height);
    radianceTexture.write(radiance, uint2(texX, texY));
}
