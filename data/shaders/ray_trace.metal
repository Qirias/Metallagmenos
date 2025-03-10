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

float3 gammaCorrect(float3 linear) {
    return pow(linear, 1.0f / 2.2f);
}

float4 sunAndSky(float3 rayDir, FrameData frameData) {
    const float3 skyColor = float3(0.02f, 0.08f, 0.2f);
    
    float3 sunDirection = normalize(frameData.sun_eye_direction.xyz);
    float3 sunColor = frameData.sun_color.xyz;
    
    float cosAngle = dot(normalize(rayDir), sunDirection);
    
    float sunIntensity = smoothstep(0.95f, 1.0f, cosAngle);
    float sunGlow = smoothstep(0.9f, 0.95f, cosAngle) * 0.2f;

    float3 finalColor = /*skyColor + (*/sunColor * sunIntensity * 0.5f/*) + (sunColor * sunGlow)*/;
    
    return float4(finalColor, 1.0f);
}

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

float2 octEncode(float3 n) {
    float2 p = n.xy * (1.0 / (abs(n.x) + abs(n.y) + abs(n.z)));
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

float4 mergeUpperCascade(texture2d<float, access::sample> upperRadianceTexture,
                                       float2 probeUV,
                                       float3 rayDir,
                                       CascadeData cascadeData,
                                       FrameData frameData) {
    uint currentCascadeLevel = cascadeData.cascadeLevel;
    
    uint upperCascadeLevel  = currentCascadeLevel + 1;
    uint upperTileSize      = cascadeData.probeSpacing * (1 << upperCascadeLevel);
    uint upperGridSizeX     = (frameData.framebuffer_width + upperTileSize - 1) / upperTileSize;
    uint upperGridSizeY     = (frameData.framebuffer_height + upperTileSize - 1) / upperTileSize;
    uint upperDirectionRegionsX = (1 << (upperCascadeLevel));
    uint upperDirectionRegionsY = (1 << (upperCascadeLevel));

    // Bilinear probe interpolation setup
    float2 upperGridCoord   = probeUV * float2(upperGridSizeX, upperGridSizeY) - 0.5f;
    int2 upperProbeBase     = int2(floor(upperGridCoord));
    float2 upperFrac        = fract(upperGridCoord);
    
    float4 bilinearWeights = float4((1.0f - upperFrac.x)    * (1.0f - upperFrac.y),
                                    upperFrac.x             * (1.0f - upperFrac.y),
                                    (1.0f - upperFrac.x)    * upperFrac.y,
                                    upperFrac.x             * upperFrac.y);

    int2 probeOffsets[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};

    // Direction from current cascade
    float2 octDir = octEncode(rayDir);
    
    // Convert to upper cascade direction grid coordinates
    float2 dirGridCoord = float2(octDir.x * upperDirectionRegionsX,
                                 octDir.y * upperDirectionRegionsY);
    int2 dirBase = int2(floor(dirGridCoord));
    float2 dirFrac = fract(dirGridCoord);
    
    // Calculate bilinear weights for direction interpolation
    float2 dirWeights = dirFrac;
    float4 dirBilinearWeights = float4((1.0f - dirWeights.x)    * (1.0f - dirWeights.y),  // bottom-left
                                       dirWeights.x             * (1.0f - dirWeights.y),  // bottom-right
                                       (1.0f - dirWeights.x)    * dirWeights.y,           // top-left
                                       dirWeights.x             * dirWeights.y            // top-right
    );
    
    // Bilinear interpolation offsets
    int2 dirOffsets[4] = {
        int2(0, 0),  // bottom-left
        int2(1, 0),  // bottom-right
        int2(0, 1),  // top-left
        int2(1, 1)   // top-right
    };
    
    float4 accumulatedRadiance = float4(0.0f);
    float totalWeight = 0.0f;
    
    // For each nearby probe
    for (int probeIdx = 0; probeIdx < 4; probeIdx++) {
        int2 probeCoord = upperProbeBase + probeOffsets[probeIdx];
        
        float probeWeight = bilinearWeights[probeIdx];
        if (probeWeight <= 0.0f) continue; // Skip probes with no contribution
        
        float4 probeRadiance = float4(0.0f);
        float2 probeUVCenter = (float2(probeCoord) + 0.5f) / float2(upperGridSizeX, upperGridSizeY);
        
        for (int dirIdx = 0; dirIdx < 4; dirIdx++) {
            int dirX = dirBase.x + dirOffsets[dirIdx].x;
            int dirY = dirBase.y + dirOffsets[dirIdx].y;
            
            // Handle wrapping at octahedral map boundaries
            dirX = ((dirX % upperDirectionRegionsX) + upperDirectionRegionsX) % upperDirectionRegionsX;
            dirY = ((dirY % upperDirectionRegionsY) + upperDirectionRegionsY) % upperDirectionRegionsY;
            
            // Calculate sample position in texture
            float2 dirUV = float2(
                (float(dirX) + 0.5f) / float(upperDirectionRegionsX),
                (float(dirY) + 0.5f) / float(upperDirectionRegionsY)
            );
            float2 dirOffset = (dirUV - 0.5f) / float2(upperGridSizeX, upperGridSizeY);
            float2 sampleUV = probeUVCenter + dirOffset;
            
            float4 sample = upperRadianceTexture.sample(samplerLinear, sampleUV);
            
            probeRadiance += sample * dirBilinearWeights[dirIdx];
        }
        
        accumulatedRadiance += probeRadiance * probeWeight;
        totalWeight += probeWeight;
    }
    
    if (totalWeight > 0.0f) {
        accumulatedRadiance /= totalWeight;
    }
    
    return accumulatedRadiance;
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
    float intervalLength = cascadeData.intervalLength;

    // Compute probe grid
    uint tileSize = probeSpacing * (1 << cascadeLevel);
    uint probeGridSizeX = (frameData.framebuffer_width + tileSize - 1) / tileSize;
    uint probeGridSizeY = (frameData.framebuffer_height + tileSize - 1) / tileSize;

    // 8 for level 0, then 16, 64, 256, etc.
    uint raysPerDim = (cascadeLevel == 0) ? 4 : (1 << (cascadeLevel + 1)); // 4, 4, 8, 16, 32, ...
    uint numRays = (cascadeLevel == 0) ? 8 : (raysPerDim * raysPerDim);   // 8, 16, 64, 256, ...
    uint totalProbes = probeGridSizeX * probeGridSizeY;
    uint totalThreads = totalProbes * numRays;

    if (tid >= totalThreads) {
        return;
    }

    uint rayIndex = tid % numRays;
    uint probeIndex = tid / numRays;
    uint probeIndexY = probeIndex / probeGridSizeX;
    uint probeIndexX = probeIndex % probeGridSizeX;

    // Map probe to screen UV
    float2 probeUV = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 probeNDC = probeUV * 2.0f - 1.0f;
    probeNDC.y = -probeNDC.y;
    float2 minMaxDepth = minMaxTexture.sample(depthSampler, probeUV).xy;
    float probeDepth = minMaxDepth.x; // (minMaxDepth.x + minMaxDepth.y) * 0.5f;
    float3 worldPos = reconstructWorldPosition(probeNDC, probeDepth,
                                               frameData.projection_matrix_inverse,
                                               frameData.inverse_view_matrix);

    if (rayIndex == 0) {
        probeData[probeIndex].position = float4(worldPos, (minMaxDepth.x != minMaxDepth.y ? 1.0f : 0.0f));
    }

    // Compute ray direction using octahedral mapping
    uint raysPerDimX = raysPerDim;
    uint raysPerDimY = raysPerDim;
    int rayX, rayY;

    if (cascadeLevel == 0) {
        // Use your original 8-ray pattern for cascade 0
        uint gridIndices[8] = {0, 3, 5, 6, 9, 10, 12, 15};
        uint gridIndex = gridIndices[rayIndex];
        rayX = gridIndex % raysPerDimX;
        rayY = gridIndex / raysPerDimY;
    } else {
        // Regular grid for higher cascades
        rayX = rayIndex % raysPerDimX;
        rayY = rayIndex / raysPerDimY;
    }

    float2 rayUV = float2(
        (rayX + 0.5f) / float(raysPerDimX),
        (rayY + 0.5f) / float(raysPerDimY)
    );
    float3 rayDir = octDecode(rayUV);

    // Map ray to tile UV
    float2 tileUV = float2(
        probeUV.x + (rayUV.x - 0.5f) * (float(tileSize) / float(frameData.framebuffer_width)),
        probeUV.y + (rayUV.y - 0.5f) * (float(tileSize) / float(frameData.framebuffer_height))
    );

    // Define cascade ranges
    const float cascadeRanges[5][2] = {
        {0.0f, 0.02f},     // Cascade 0: 0 - 0.02 unit
        {0.016f, 0.08f},   // Cascade 1: 0.016 - 0.08 units
        {0.064f, 0.32f},   // Cascade 2: 0.064 - 0.32 units
        {0.256f, 1.28f},   // Cascade 3: 0.256 - 1.28 units
        {1.024f, 5.12f}    // Cascade 4: 1.024 - 5.12 units
    };

    float intervalStart = cascadeRanges[cascadeLevel][0]*intervalLength;
    float intervalEnd = cascadeRanges[cascadeLevel][1]*intervalLength;

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
    bool enableSky = true;
    float4 radiance = float4(0.0);
    if (result.type != intersection_type::none) {
        unsigned int primitiveIndex = result.primitive_id;
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];
        radiance = (triangle.colors[0].a == -1.0f) ? float4(triangle.colors[0].rgb, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
    } else {
        // No intersection - Apply sky for higher cascades
        if (cascadeLevel >= cascadeData.maxCascade - 1 && enableSky) {
            radiance = sunAndSky(rayDir, frameData);
        } else {
            radiance = float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    // Merge with upper cascade
    float4 upperRadiance = float4(0.0);
    if (cascadeLevel < cascadeData.maxCascade) {
        upperRadiance = mergeUpperCascade(
            upperRadianceTexture,
            probeUV,
            rayDir,
            cascadeData,
            frameData
        );

        if (result.type == intersection_type::none) {
            // If no hit in current cascade, use upper cascade
            if (cascadeLevel == cascadeData.maxCascade - 1 && enableSky) {
                if (upperRadiance.a < 0.9f) {
                    float blendFactor = 1.0f - upperRadiance.a;
                    upperRadiance = mix(upperRadiance, radiance, blendFactor);
                    upperRadiance.a = max(upperRadiance.a, 0.9f);
                }
            }
            radiance = upperRadiance;
        } else {
            // There was a hit, blend with upper cascade
            radiance.rgb += upperRadiance.rgb * radiance.a;
            radiance.a *= upperRadiance.a;
        }
    }

    rayData[rayDataIndex].color = float4(1.0, 0.0, 0.0, 1.0);

    // Write to radiance texture
    uint texX = uint(tileUV.x * frameData.framebuffer_width);
    uint texY = uint(tileUV.y * frameData.framebuffer_height);

    if (cascadeLevel == 0) {
        float3 gammaCorrected = gammaCorrect(radiance.rgb);
        radianceTexture.write(float4(gammaCorrected, radiance.a), uint2(texX, texY));
    } else {
        radianceTexture.write(radiance, uint2(texX, texY));
    }
}
