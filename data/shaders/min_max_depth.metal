#include <metal_stdlib>
using namespace metal;

kernel void initMinMaxDepthKernel(texture2d<float, access::read>    depthTexture    [[texture(0)]],
                                  texture2d<float, access::write>   minMaxTexture   [[texture(1)]],
                                  uint2                             gid             [[thread_position_in_grid]]) {
    if (gid.x >= minMaxTexture.get_width() || gid.y >= minMaxTexture.get_height()) return;

    float depth = depthTexture.read(gid).r;
    minMaxTexture.write(depth, gid, 0);
    minMaxTexture.write(depth, gid, 1);
}

kernel void minMaxDepthKernel(texture2d<float, access::read>    srcTexture [[texture(0)]],
                              texture2d<float, access::write>   dstTexture [[texture(1)]],
                              uint2                             gid        [[thread_position_in_grid]]) {
    int2 dstSize = int2(dstTexture.get_width(), dstTexture.get_height());
    
    if (int(gid.x) >= dstSize.x || int(gid.y) >= dstSize.y) return;
    
    // Compute corresponding texel in the higher mip level
    int2 srcCoord = int2(gid) * 2;
    
    // Read 2x2 block from higher mip level
    float2 depth00 = srcTexture.read(uint2(srcCoord)).rg;
    float2 depth10 = srcTexture.read(uint2(srcCoord + int2(1, 0))).rg;
    float2 depth01 = srcTexture.read(uint2(srcCoord + int2(0, 1))).rg;
    float2 depth11 = srcTexture.read(uint2(srcCoord + int2(1, 1))).rg;
    
    float newMinDepth = min(depth00.r, min(depth10.r, min(depth01.r, depth11.r)));
    float newMaxDepth = max(depth00.g, max(depth10.g, max(depth01.g, depth11.g)));
    
    dstTexture.write(float4(newMinDepth, newMaxDepth, 0, 0), gid);
}
