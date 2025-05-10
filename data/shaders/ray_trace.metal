#define METAL
#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"
#include "common.hpp"

struct TriangleResources {
    struct TriangleData {
        float4 normals[3];
        float4 colors[3];
    };
    device TriangleData* triangles;
};

// https://github.com/tooll3/Resources/blob/master/hash-functions.hlsl
float3 hash33(float3 p3)
{
    p3 = fract(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy + p3.yxx)*p3.zyx);
}

float4 sun(float3 rayDir, FrameData frameData) {
    float3 sunDirection = normalize(-frameData.sun_eye_direction.xyz);
    float3 sunColor = frameData.sun_color.rgb;
    
    float sunDot = dot(rayDir, sunDirection);
    const float sunSize = 0.97f;
    
    float sunDisk = (sunDot > sunSize) ? 1.0f : 0.0f;
    float intensity = frameData.sun_specular_intensity;
    
    return float4(sunColor * sunDisk * intensity, 1.0f);
}

float4 sky(float3 rayDir, FrameData frameData) {
    const float3 skyZenithColor = float3(0.0, 0.4, 0.8);
    const float3 skyHorizonColor = float3(0.3, 0.6, 0.8);
    
    float upDot = max(0.0f, rayDir.y);
    float3 skyGradient = mix(skyHorizonColor, skyZenithColor, pow(upDot, 0.5f));
    
    float skyIntensity = frameData.sun_specular_intensity * 0.5f;
    float skyMask = (rayDir.y > 0.0f) ? 1.0f : 0.0f;

    float3 finalSkyColor = skyGradient * skyIntensity;
    
    return float4(finalSkyColor * skyMask, 1.0f);
}

float4 skyAndSun(float3 rayDir, FrameData frameData, CascadeData cascadeData) {
    float4 result = float4(0.0f, 0.0f, 0.0f, 1.0f);
    
    if (cascadeData.enableSun) {
        result += sun(rayDir, frameData);
    }
    
    if (cascadeData.enableSky) {
        result += sky(rayDir, frameData);
    }
    
    return result;
}

float3 reconstructWorldPositionFromLinearDepth(float2 ndc, float linearDepth, float4x4 projection_inverse, float4x4 view_inverse) {
    float4 clipPos = float4(ndc.x, ndc.y, -1.0, 1.0);
    float4 viewPos = projection_inverse * clipPos;
    viewPos /= viewPos.w;
    
    float scale = linearDepth / fabs(viewPos.z);
    float depthBias = 0.98; // depth bias to avoid acne

    float3 viewPosAtDepth = viewPos.xyz * (scale * depthBias);
    
    float4 worldPos = view_inverse * float4(viewPosAtDepth, 1.0);
    return worldPos.xyz;
}

// https://www.shadertoy.com/view/4XXSWS
// Project a point onto a line and return the parametric distance
float projectLinePerpendicular(float3 lineStart, float3 lineEnd, float3 point) {
    float3 line = lineEnd - lineStart;
    float lineLength2 = dot(line, line);
    
    return saturate(dot(point - lineStart, line) / lineLength2);
}

// Calculate 3D-aware bilinear ratios using iterative approach
float2 getBilinear3dRatioIter(float3 srcPoints[4], float3 dstPoint, float2 initRatio, int iterCount) {
    float2 ratio = initRatio;
    
    for (int i = 0; i < iterCount; i++) {
        // Interpolate along Y and find X ratio
        float3 mixedY1 = mix(srcPoints[0], srcPoints[2], ratio.y);
        float3 mixedY2 = mix(srcPoints[1], srcPoints[3], ratio.y);
        ratio.x = projectLinePerpendicular(mixedY1, mixedY2, dstPoint);
        
        // Interpolate along X and find Y ratio
        float3 mixedX1 = mix(srcPoints[0], srcPoints[1], ratio.x);
        float3 mixedX2 = mix(srcPoints[2], srcPoints[3], ratio.x);
        ratio.y = projectLinePerpendicular(mixedX1, mixedX2, dstPoint);
    }
    
    return ratio;
}

float4 mergeUpperCascade(texture2d<float, access::sample> upperRadianceTexture,
                         texture2d<float, access::sample> depthTexture,
                         float2 probeUV,
                         float3 rayDir,
                         float currentDepth,
                         float3 currentWorldPos,
                         CascadeData cascadeData,
                         FrameData frameData) {
    uint currentCascadeLevel = cascadeData.cascadeLevel;
    
    // Calculate upper cascade parameters
    uint upperCascadeLevel  = currentCascadeLevel + 1;
    uint upperTileSize      = 4 * (1 << upperCascadeLevel);
    uint upperGridSizeX     = (frameData.framebuffer_width + upperTileSize - 1) / upperTileSize;
    uint upperGridSizeY     = (frameData.framebuffer_height + upperTileSize - 1) / upperTileSize;
    uint upperRaysPerDim    = 1 << (upperCascadeLevel + 2);

    // Bilinear probe interpolation setup
    float2 upperGridCoord   = probeUV * float2(upperGridSizeX, upperGridSizeY) - 0.5f;
    int2 upperProbeBase     = int2(floor(upperGridCoord));
    float2 upperFrac        = fract(upperGridCoord);

    int2 probeOffsets[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};

    // Direction from current cascade
    float2 octDir = octEncode(rayDir);
    
    // Convert to upper cascade direction grid coordinates
    float2 dirGridCoord = float2(octDir.x * upperRaysPerDim, octDir.y * upperRaysPerDim);
    int2 dirBase = int2(floor(dirGridCoord));
    float2 dirFrac = fract(dirGridCoord);
    
    float4 dirBilinearWeights = float4((1.0f - dirFrac.x)   * (1.0f - dirFrac.y),
                                       dirFrac.x            * (1.0f - dirFrac.y),
                                       (1.0f - dirFrac.x)   * dirFrac.y,
                                       dirFrac.x            * dirFrac.y);
    
    float4 upperProbeDepths;
    int2 probeCoord[4];
    float2 probeUVCenter[4];
    float3 probeWorldPos[4];
    
    // Gather probe data
    for (int i = 0; i < 4; i++) {
        // Clamp to handle edge cases
        probeCoord[i] = clamp(upperProbeBase + probeOffsets[i], int2(0), int2(upperGridSizeX - 1, upperGridSizeY - 1));
        probeUVCenter[i] = (float2(probeCoord[i]) + 0.5f) / float2(upperGridSizeX, upperGridSizeY);
        upperProbeDepths[i] = depthTexture.sample(depthSampler, probeUVCenter[i]).x;
        
        float2 probeNDC = probeUVCenter[i] * 2.0f - 1.0f;
        probeNDC.y = -probeNDC.y;
        probeWorldPos[i] = reconstructWorldPositionFromLinearDepth(probeNDC, upperProbeDepths[i], frameData.projection_matrix_inverse, frameData.view_matrix_inverse);
    }
    
    float2 ratio3d = getBilinear3dRatioIter(probeWorldPos, currentWorldPos, upperFrac, 2);
    float4 bilinearWeights = float4((1.0f - ratio3d.x)   * (1.0f - ratio3d.y),
                                     ratio3d.x           * (1.0f - ratio3d.y),
                                    (1.0f - ratio3d.x)   * ratio3d.y,
                                     ratio3d.x           * ratio3d.y);
  
    // Bilinear interpolation offsets for direction sampling
    int2 dirOffsets[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};
    
    float4 accumulatedRadiance = float4(0.0f);
    for (int probeIdx = 0; probeIdx < 4; probeIdx++) {
        float probeWeight = bilinearWeights[probeIdx];
        if (probeWeight <= 0.0f) continue;
        
        float4 probeRadiance = float4(0.0f);
        float2 probeUVCenterLocal = probeUVCenter[probeIdx];
        
        for (int dirIdx = 0; dirIdx < 4; dirIdx++) {
            int dirX = dirBase.x + dirOffsets[dirIdx].x;
            int dirY = dirBase.y + dirOffsets[dirIdx].y;

            // rayDir already had the offset so it's not needed here
            float2 dirUV = float2(float(dirX) / float(upperRaysPerDim),
                                  float(dirY) / float(upperRaysPerDim));
            
            float2 dirOffset = (dirUV - 0.5f) / float2(upperGridSizeX, upperGridSizeY);
            float2 sampleUV = probeUVCenterLocal + dirOffset;
            
            float4 sample = upperRadianceTexture.sample(samplerLinear, sampleUV);
            probeRadiance += sample * dirBilinearWeights[dirIdx];
        }
        
        accumulatedRadiance += probeRadiance * probeWeight;
    }
    
    return accumulatedRadiance;
}

// Manually uncomment anything related to debugging if you want to see the probe data
kernel void raytracingKernel(texture2d<float, access::write>    radianceTexture         [[texture(TextureIndexRadiance)]],
                             texture2d<float, access::sample>   upperRadianceTexture    [[texture(TextureIndexRadianceUpper)]],
                             texture2d<float, access::read>     historyTexture          [[texture(TextureIndexHistory)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                    constant CascadeData&                       cascadeData             [[buffer(BufferIndexCascadeData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
                      device ProbeRay*                          rayData                 [[buffer(BufferIndexProbeRayData)]],
                      device ProbeAccum*                        probeAccum              [[buffer(BufferIndexProbeAccumData)]],
                             texture2d<float, access::sample>   depthTexture            [[texture(TextureIndexDepthTexture)]],
                             texture2d<float, access::sample>   historyDepthTexture     [[texture(TextureIndexHistoryDepthTexture)]],
                             uint                               tid                     [[thread_position_in_grid]]) {
    const uint probeSpacing = cascadeData.probeSpacing;
    uint cascadeLevel = cascadeData.cascadeLevel;
    float intervalLength = cascadeData.intervalLength;

    // Compute probe grid
    uint tileSize = probeSpacing * (1 << cascadeLevel);
    uint probeGridSizeX = (frameData.framebuffer_width + tileSize - 1) / tileSize;
    uint probeGridSizeY = (frameData.framebuffer_height + tileSize - 1) / tileSize;

    uint raysPerDim = (1 << (cascadeLevel + 2)); // 4, 8, 16, ...
    uint numRays = (raysPerDim * raysPerDim); // 16, 64, 256, ...
    uint totalProbes = probeGridSizeX * probeGridSizeY;
    uint totalThreads = totalProbes * numRays;

    if (tid >= totalThreads) {
        return;
    }

    // Ray and probe indices
    uint rayIndex = tid % numRays;
    uint probeIndex = tid / numRays;
    uint probeIndexX = probeIndex % probeGridSizeX;
    uint probeIndexY = probeIndex / probeGridSizeX;
    
    // Map probe to screen UV center
    float2 probeUV = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 probeNDC = probeUV * 2.0f - 1.0f;
    probeNDC.y = -probeNDC.y; // Flip Y axis for Metal API
    float probeDepth = depthTexture.sample(depthSampler, probeUV).x;
    
    if (probeDepth >= frameData.far_plane - 0.1) {
        return;
    }
    
    float3 worldPos = reconstructWorldPositionFromLinearDepth(probeNDC, probeDepth,
                                                              frameData.projection_matrix_inverse,
                                                              frameData.view_matrix_inverse);
    
    // Handle temporal reprojection and accumulation update for first ray of each probe
    if (rayIndex == 0 && cascadeData.enableTA) {
        float prevProbeDepth = historyDepthTexture.sample(depthSampler, probeUV).x;
        bool isHistoryValid = false;
        
        if (prevProbeDepth < frameData.far_plane - 0.1) {
            float3 prevWorldPos = reconstructWorldPositionFromLinearDepth(probeNDC, prevProbeDepth,
                                                                          frameData.prev_projection_matrix_inverse,
                                                                          frameData.prev_view_matrix_inverse);
            
            // Project previous world position to current frame's clip space
            float4 prevWorldInCurrentClip = frameData.projection_matrix * frameData.view_matrix * float4(prevWorldPos, 1.0);
            float2 prevWorldNDC = prevWorldInCurrentClip.xy / prevWorldInCurrentClip.w;
            
            float2 ndcDelta = prevWorldNDC - probeNDC;
            
            float2 pixelDelta = ndcDelta * float2(frameData.framebuffer_width, frameData.framebuffer_height) * 0.5f;
            float pixelDistance = length(pixelDelta);
            
            float depthDelta = abs(probeDepth - prevProbeDepth);
            
            float pixelThreshold = float(tileSize) * 0.8f; // If it has moved between the cascade's probe spacing

            float depthRange = frameData.far_plane - frameData.near_plane;
            float targetPercentage = 0.1f;
            float baseDepthThreshold = depthRange * targetPercentage;
            float depthThreshold = baseDepthThreshold * (1 << cascadeLevel);
            
            isHistoryValid = (pixelDistance < pixelThreshold) && (depthDelta < depthThreshold);
        }
        
        probeAccum[probeIndex].isHistoryValid = isHistoryValid;
        
        if (isHistoryValid) {
            probeAccum[probeIndex].temporalAccumulationCount = min(probeAccum[probeIndex].temporalAccumulationCount + 1.0f, frameData.maxTemporalAccumulationFrames);
        } else {
            // Invalid history - reset counter
            probeAccum[probeIndex].temporalAccumulationCount = 1.0f;
        }
        
        probeData[probeIndex].position = float4(worldPos, 0.0f);
    }

    // Ray index in a 2D grid inside the octahedron
    int rayX = rayIndex % raysPerDim;
    int rayY = rayIndex / raysPerDim;
    
    float2 rayUV;
    float3 rayDir;
    
    if (cascadeData.enableTA) {
        // Apply temporal jitter to ray directions for better sampling over time
        float3 frame_hash = hash33(float3(frameData.frameNumber));
        float2 jitter = (frame_hash.xy - 0.5) / float(raysPerDim);
        rayUV = (float2(rayX + 0.5f, rayY + 0.5f) + jitter) / float(raysPerDim);
        rayDir = octDecode(rayUV);
    } else {
        rayUV = float2((rayX+0.5f) / float(raysPerDim), (rayY+0.5f) / float(raysPerDim));
        rayDir = octDecode(rayUV);
    }

    
    // Calculate tile UV for this ray
    float2 tileUV = float2(
        probeUV.x + (rayUV.x - 0.5f) * (float(tileSize) / float(frameData.framebuffer_width)),
        probeUV.y + (rayUV.y - 0.5f) * (float(tileSize) / float(frameData.framebuffer_height))
    );

    // Calculate cascade interval range
    const float baseCascadeRange = 0.016f;
    const float cascadeRangeMultiplier = 4.0f;
    float cascadeStartRange = (cascadeLevel == 0) ? 0.0f : (baseCascadeRange * pow(cascadeRangeMultiplier, float(cascadeLevel - 1)));
    float cascadeEndRange = baseCascadeRange * pow(cascadeRangeMultiplier, float(cascadeLevel));
    float intervalStart = cascadeStartRange * intervalLength;
    float intervalEnd = cascadeEndRange * intervalLength;
    
    // Set up and trace ray
    ray ray;
    ray.origin = worldPos;
    ray.direction = rayDir;
    ray.min_distance = intervalStart;
    ray.max_distance = intervalEnd;

    intersector<triangle_data> intersector;
    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);
    
    intervalStart *= intervalLength;
    intervalEnd *= intervalLength;
    float3 startPoint = worldPos + rayDir * intervalStart;
    float3 endPoint = worldPos + rayDir * intervalEnd;

    uint rayDataIndex = probeIndex * numRays + rayIndex;
    rayData[rayDataIndex].intervalStart = float4(startPoint, 1.0);
    rayData[rayDataIndex].intervalEnd = float4(endPoint, 1.0);

    bool sampleSunOrSky = cascadeData.enableSky || cascadeData.enableSun;
    float4 radiance = float4(0.0);
    float occlusion;
    
    if (result.type != intersection_type::none) {
        // Hit an object
        unsigned int primitiveIndex = result.primitive_id;
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];
        
        radiance = (triangle.colors[0].a == -1.0f) ? float4(triangle.colors[0].rgb, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
        occlusion = 0.0;
        
        if (triangle.colors[0].a == -1.0f)
            rayData[rayDataIndex].color = float4(1.0, 0.0, 0.0, 1.0); // Red for emissive
        else
            rayData[rayDataIndex].color = float4(0.0, 0.0, 1.0, 1.0); // Blue for non-emissive
    } else {
        occlusion = 1.0f;
        
        // For highest cascade, sample sky if enabled
        if ((cascadeLevel == cascadeData.maxCascade) && sampleSunOrSky) {
            radiance = skyAndSun(rayDir, frameData, cascadeData);
        } else {
            radiance = float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    float4 upperRadiance = float4(0.0);
    if (cascadeLevel < cascadeData.maxCascade) {
        upperRadiance = mergeUpperCascade(upperRadianceTexture,
                                          depthTexture,
                                          probeUV,
                                          rayDir,
                                          probeDepth,
                                          worldPos,
                                          cascadeData,
                                          frameData);

        if (result.type == intersection_type::none) {
            // No hit in current cascade, use upper cascade
            rayData[rayDataIndex].color = float4(0.4, 0.4, 0.4, 1.0);
            radiance = upperRadiance;
        } else {
            // Hit in current cascade, blend with upper cascade based on occlusion
            radiance.rgb += upperRadiance.rgb * occlusion;
            radiance.a *= upperRadiance.a;
        }
    }
    
    uint texX = uint(tileUV.x * frameData.framebuffer_width);
    uint texY = uint(tileUV.y * frameData.framebuffer_height);
    
    if (cascadeLevel != 0 || !cascadeData.enableTA) {
        // Higher cascades - just write directly
        radianceTexture.write(radiance, uint2(texX, texY));
    } else {
        float4 historyColor = historyTexture.read(uint2(texX, texY));
    
        bool isHistoryValid = probeAccum[probeIndex].isHistoryValid;
        float frameCount = probeAccum[probeIndex].temporalAccumulationCount;
        
        float4 accumulatedColor;
        
        if (isHistoryValid) {
            // Calculate blend factor (closer to 1.0 as more frames accumulate)
            float modulationFactor = frameCount / (frameCount + 1.0);
            
            // Cap at max frames
            if (frameCount >= frameData.maxTemporalAccumulationFrames) {
                modulationFactor = frameData.maxTemporalAccumulationFrames /
                                 (frameData.maxTemporalAccumulationFrames + 1.0);
            }
            
            accumulatedColor = mix(radiance, historyColor, modulationFactor);
        } else {
            accumulatedColor = radiance;
        }
        
        radianceTexture.write(accumulatedColor, uint2(texX, texY));
    }
}
