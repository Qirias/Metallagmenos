#define METAL
#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

constant float PI4 = 12.56637; // Surface area of unit sphere
constant uint ANGULAR_FACTOR = 4;
constant uint C0_INTERVAL_COUNT = 16;
constant float MAX_SOLID_ANGLE = 0.005;

struct TriangleResources {
    struct TriangleData {
        float4 normals[3];
        float4 colors[3];
    };
    device TriangleData* triangles;
};

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
    float3 sunDirection = normalize(-frameData.sun_eye_direction.xyz);
    float3 sunColor = frameData.sun_color.rgb;

    const float3 skyZenithColor = float3(0.0, 0.4, 0.8);
    const float3 skyHorizonColor = float3(0.3, 0.6, 0.8);
    const float sunScatteringFactor = 0.8f;
    
    float upDot = max(0.0f, rayDir.y);
    
    float sunDot = max(0.0f, dot(rayDir, sunDirection));
    float3 skyGradient = mix(skyHorizonColor, skyZenithColor, pow(upDot, 0.5f));
    
    float scattering = pow(sunDot, 8.0f) * sunScatteringFactor;
    
    float skyIntensity = frameData.sun_specular_intensity * 0.5f;
    float skyMask = (rayDir.y > 0.0f) ? 1.0f : 0.0f;

    float3 finalSkyColor = (skyGradient + scattering * sunColor) * skyIntensity;
    
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

float3 reconstructWorldPositionFromLinearDepth(float2 ndc, float linearDepth,
                                             float near, float far,
                                             float4x4 invProjection,
                                             float4x4 invView) {
    float4 clipPos = float4(ndc.x, ndc.y, -1.0, 1.0);
    float4 viewPos = invProjection * clipPos;
    viewPos /= viewPos.w;
    
    float scale = linearDepth / fabs(viewPos.z);
    float depthBias = 0.999;
    
    float3 viewPosAtDepth = viewPos.xyz * (scale * depthBias);
    
    float4 worldPos = invView * float4(viewPosAtDepth, 1.0);
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
                         texture2d<float, access::sample> depthTexture,
                         float2 probeUV,
                         float3 rayDir,
                         float currentDepth,
                         CascadeData cascadeData,
                         FrameData frameData) {
    uint currentCascadeLevel = cascadeData.cascadeLevel;
    
    uint upperCascadeLevel  = currentCascadeLevel + 1;
    uint upperTileSize      = 4 * (1 << upperCascadeLevel);
    uint upperGridSizeX     = (frameData.framebuffer_width + upperTileSize - 1) / upperTileSize;
    uint upperGridSizeY     = (frameData.framebuffer_height + upperTileSize - 1) / upperTileSize;
    uint upperRaysPerDim    = 1 << (upperCascadeLevel + 2);

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
    float2 dirGridCoord = float2(octDir.x * upperRaysPerDim, octDir.y * upperRaysPerDim);
    int2 dirBase = int2(floor(dirGridCoord));
    float2 dirFrac = fract(dirGridCoord);
    
    float4 dirBilinearWeights = float4((1.0f - dirFrac.x)    * (1.0f - dirFrac.y),
                                       dirFrac.x             * (1.0f - dirFrac.y),
                                       (1.0f - dirFrac.x)    * dirFrac.y,
                                       dirFrac.x             * dirFrac.y);
    
    float4 upperProbeDepths;
    int2 probeCoord[4];
    float2 probeUVCenter[4];
    
    for (int i = 0; i < 4; i++) {
        probeCoord[i] = upperProbeBase + probeOffsets[i];
        probeUVCenter[i] = (float2(probeCoord[i]) + 0.5f) / float2(upperGridSizeX, upperGridSizeY);
        upperProbeDepths[i] = depthTexture.sample(depthSampler, probeUVCenter[i]).x;
    }

    // Edge detection
    float mind = min(min(upperProbeDepths.x, upperProbeDepths.y), min(upperProbeDepths.z, upperProbeDepths.w));
    float maxd = max(max(upperProbeDepths.x, upperProbeDepths.y), max(upperProbeDepths.z, upperProbeDepths.w));
    float diffd = maxd - mind;
    float avg = dot(upperProbeDepths, float4(0.25f));
    bool d_edge = (diffd / avg) > 0.2;
    
    float4 w = bilinearWeights;
    if (d_edge) {
        float4 dd = abs(upperProbeDepths - float4(currentDepth));
        w *= float4(1.0f) / (dd + float4(0.0001f));
    }
    
    float wsum = w.x + w.y + w.z + w.w;
    w /= wsum;
    
    // Bilinear interpolation offsets
    int2 dirOffsets[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};
    
    float4 accumulatedRadiance = float4(0.0f);
    for (int probeIdx = 0; probeIdx < 4; probeIdx++) {
        float probeWeight = w[probeIdx];
        if (probeWeight <= 0.0f) continue;
        
        float4 probeRadiance = float4(0.0f);
        float2 probeUVCenterLocal = probeUVCenter[probeIdx];
        
        for (int dirIdx = 0; dirIdx < 4; dirIdx++) {
            int dirX = dirBase.x + dirOffsets[dirIdx].x;
            int dirY = dirBase.y + dirOffsets[dirIdx].y;
            
            dirX = ((dirX % upperRaysPerDim) + upperRaysPerDim) % upperRaysPerDim;
            dirY = ((dirY % upperRaysPerDim) + upperRaysPerDim) % upperRaysPerDim;
            
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

kernel void raytracingKernel(texture2d<float, access::write>    radianceTexture         [[texture(TextureIndexRadiance)]],
                             texture2d<float, access::sample>   upperRadianceTexture    [[texture(TextureIndexRadianceUpper)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                    constant CascadeData&                       cascadeData             [[buffer(BufferIndexCascadeData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
//                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
//                      device ProbeRay*                          rayData                 [[buffer(BufferIndexProbeRayData)]],
                             texture2d<float, access::sample>   depthTexture            [[texture(TextureIndexDepthTexture)]],
                             uint                               tid                     [[thread_position_in_grid]]) {
    const uint probeSpacing = cascadeData.probeSpacing;
    uint cascadeLevel = cascadeData.cascadeLevel;
    float intervalLength = cascadeData.intervalLength;

    // Compute probe grid
    uint tileSize = probeSpacing * (1 << cascadeLevel);
    uint probeGridSizeX = (frameData.framebuffer_width + tileSize - 1) / tileSize;
    uint probeGridSizeY = (frameData.framebuffer_height + tileSize - 1) / tileSize;

    uint raysPerDim =  (1 << (cascadeLevel + 2)); // 4, 8, 16, ...
    uint numRays = (raysPerDim * raysPerDim); // 16, 64, 256, ...
    uint totalProbes = probeGridSizeX * probeGridSizeY;
    uint totalThreads = totalProbes * numRays;

    if (tid >= totalThreads) {
        return;
    }

    uint rayIndex = tid % numRays;
    uint probeIndex = tid / numRays;
    uint probeIndexX = probeIndex % probeGridSizeX;
    uint probeIndexY = probeIndex / probeGridSizeX;
    
    // Map probe to screen UV
    float2 probeUV = (float2(probeIndexX, probeIndexY) + 0.5f) / float2(probeGridSizeX, probeGridSizeY);
    float2 probeNDC = probeUV * 2.0f - 1.0f;
    probeNDC.y = -probeNDC.y;
    float probeDepth = depthTexture.sample(depthSampler, probeUV).x;
    float3 worldPos = reconstructWorldPositionFromLinearDepth(probeNDC, probeDepth, frameData.near_plane, frameData.far_plane,
                                                              frameData.projection_matrix_inverse,
                                                              frameData.view_matrix_inverse);

//    if (rayIndex == 0) {
//        probeData[probeIndex].position = float4(worldPos, 0.0f);
//    }

    int rayX = rayIndex % raysPerDim;
    int rayY = rayIndex / raysPerDim;

    float2 rayUV = float2(
        (rayX+0.5f) / float(raysPerDim),
        (rayY+0.5f) / float(raysPerDim)
    );
    
    float3 rayDir = octDecode(rayUV);
    
    float2 tileUV = float2(
        probeUV.x + (rayUV.x - 0.5f) * (float(tileSize) / float(frameData.framebuffer_width)),
        probeUV.y + (rayUV.y - 0.5f) * (float(tileSize) / float(frameData.framebuffer_height))
    );

    // https://github.com/mxcop/src-dgi/blob/main/assets/shaders/surfels/cascade.slang
    float baseIntervalLength = MAX_SOLID_ANGLE * C0_INTERVAL_COUNT / PI4;

    // Scale intervals with angular resolution
    float intervalStart, intervalEnd;
    if (cascadeLevel == 0) {
        intervalStart = 0.0f;
        intervalEnd = baseIntervalLength * float(ANGULAR_FACTOR);
    } else {
        float start_scale = pow(float(ANGULAR_FACTOR), float(cascadeLevel));
        intervalStart = baseIntervalLength * start_scale;
        intervalEnd = baseIntervalLength * start_scale * float(ANGULAR_FACTOR);
    }

    intervalStart *= intervalLength;
    intervalEnd *= intervalLength;
    
    ray ray;
    ray.origin = worldPos;
    ray.direction = rayDir;
    ray.min_distance = intervalStart;
    ray.max_distance = intervalEnd;

    intersector<triangle_data> intersector;
    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);

//    float3 startPoint = worldPos + rayDir * intervalStart;
//    float3 endPoint = worldPos + rayDir * intervalEnd;

//    uint rayDataIndex = probeIndex * numRays + rayIndex;
//    rayData[rayDataIndex].intervalStart = float4(startPoint, 1.0);
//    rayData[rayDataIndex].intervalEnd = float4(endPoint, 1.0);

    // Direct radiance from current cascade
    bool sampleSunOrSky = cascadeData.enableSky || cascadeData.enableSun;
    float4 radiance = float4(0.0);
    float occlusion;
    
    if (result.type != intersection_type::none) {
        unsigned int primitiveIndex = result.primitive_id;
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];
        radiance = (triangle.colors[0].a == -1.0f) ? float4(triangle.colors[0].rgb, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
        occlusion = 0.0;
        
    } else {
        occlusion = 1.0f;
        // No intersection - Apply sky for higher cascades
        if (cascadeLevel == cascadeData.maxCascade  && sampleSunOrSky) {
            radiance = skyAndSun(rayDir, frameData, cascadeData);
        } else {
            radiance = float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    // Merge with upper cascade
    float4 upperRadiance = float4(0.0);
    if (cascadeLevel < cascadeData.maxCascade) {
        upperRadiance = mergeUpperCascade(upperRadianceTexture,
                                          depthTexture,
                                          probeUV,
                                          rayDir,
                                          probeDepth,
                                          cascadeData,
                                          frameData);

        if (result.type == intersection_type::none) {
            // If no hit in current cascade, use upper cascade
            radiance = upperRadiance;
        } else {
            // There was a hit, blend with upper cascade
            radiance.rgb += upperRadiance.rgb * occlusion;
            radiance.a *= upperRadiance.a;
        }
    }
    
    uint texX = uint(tileUV.x * frameData.framebuffer_width);
    uint texY = uint(tileUV.y * frameData.framebuffer_height);
    
    radianceTexture.write(radiance, uint2(texX, texY));
}
