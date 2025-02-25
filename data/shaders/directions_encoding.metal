#include <metal_stdlib>
using namespace metal;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

float2 octEncode(float3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = (n.z >= 0.0) ? n.xy : (1.0 - abs(n.yx)) * sign(n.xy);
    return n.xy * 0.5 + 0.5;
}

float3 getRayDirection(int rayIndex, int level) {
    int hrings = 4 << level;
    int vrings = 4 << level;
    
    float a0 = rayIndex / vrings;
    float a1 = rayIndex % vrings;
    
    float angle0 = 2.0 * M_PI_F * (a0 + 0.5) / float(hrings);
    float angle1 = 2.0 * M_PI_F * (a1 + 0.5) / float(vrings);
    
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

kernel void direction_encoding_kernel(texture2d<float, access::write>  directionTexture     [[texture(TextureIndexDirectionEncoding)]],
                          constant    FrameData&                       frameData            [[buffer(BufferIndexFrameData)]],
                          constant    int&                             cascadeLevel         [[buffer(0)]],
                                      uint                             tid                  [[thread_position_in_grid]]) {
    uint probeSpacing = 2;
    
    uint tileSize = probeSpacing * (1 << cascadeLevel);
    uint probeGridSizeX = (frameData.framebuffer_width + tileSize - 1) / tileSize;
    uint probeGridSizeY = (frameData.framebuffer_height + tileSize - 1) / tileSize;
    
    uint numRays = 8 * (1 << (2 * cascadeLevel));

    uint totalProbes = probeGridSizeX * probeGridSizeY;
    uint totalThreads = totalProbes * numRays;
    
    if (tid >= totalThreads)
        return;
    
    uint rayIndex = tid % numRays;
    uint probeIndex = tid / numRays;
    uint probeIndexY = probeIndex / probeGridSizeX;
    uint probeIndexX = probeIndex % probeGridSizeX;

    if (probeIndexX >= probeGridSizeX || probeIndexY >= probeGridSizeY) {
        return;
    }
    
    float3 rayDir = getRayDirection(rayIndex, cascadeLevel);
    float2 encodedDir = octEncode(rayDir);

    uint textureWidth = directionTexture.get_width();
    uint textureHeight = directionTexture.get_height();
    
    uint linearRayIndex = probeIndexY * probeGridSizeX * numRays + probeIndexX * numRays + rayIndex;
    
    uint texX = linearRayIndex % textureWidth;
    uint texY = linearRayIndex / textureWidth;
    
    directionTexture.write(float4(encodedDir, 0.0, 1.0), uint2(texX, texY));
}
