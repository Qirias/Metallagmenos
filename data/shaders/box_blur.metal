#define METAL
#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

#include "vertexData.hpp"
#include "shaderTypes.hpp"
#include "shaderCommon.hpp"

kernel void horizontalBlurKernel(texture2d<float, access::read>     inputTexture    [[texture(TextureIndexRadianceUpper)]],
                                 texture2d<float, access::write>    outputTexture   [[texture(TextureIndexRadiance)]],
                        constant FrameData&                         frameData       [[buffer(BufferIndexFrameData)]],
                                 uint2                              gid             [[thread_position_in_grid]]) {
    if (gid.x >= frameData.framebuffer_width || gid.y >= frameData.framebuffer_height) {
        return;
    }

    const int radius = 9;
    float4 sum = float4(0.0);
    int count = 0;
    
    for (int x = -radius; x <= radius; x++) {
        uint2 samplePos = uint2(gid.x + x, gid.y);
        
        if (samplePos.x >= 0u && samplePos.x < frameData.framebuffer_width) {
            sum += inputTexture.read(uint2(samplePos));
            count++;
        }
    }

    float4 blurredColor = sum/float(count);
    outputTexture.write(blurredColor, gid);
}

kernel void verticalBlurKernel(texture2d<float, access::read>     inputTexture    [[texture(TextureIndexRadianceUpper)]],
                                 texture2d<float, access::write>    outputTexture   [[texture(TextureIndexRadiance)]],
                        constant FrameData&                         frameData       [[buffer(BufferIndexFrameData)]],
                                 uint2                              gid             [[thread_position_in_grid]]) {
    if (gid.x >= frameData.framebuffer_width || gid.y >= frameData.framebuffer_height) {
        return;
    }
    
    const int radius = 9;
    float4 sum = float4(0.0);
    int count = 0;
    
    for (int y = -radius; y <= radius; y++) {
        uint2 samplePos = uint2(gid.x, gid.y + y);
        
        if (samplePos.y >= 0u && samplePos.y < frameData.framebuffer_height) {
            sum += inputTexture.read(uint2(samplePos));
            count++;
        }
    }
    
    float4 blurredColor = sum/float(count);
    outputTexture.write(blurredColor, gid);
}
