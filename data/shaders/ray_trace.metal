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

kernel void raytracingKernel(texture2d<float, access::write>    rayTracingTexture       [[texture(TextureIndexRaytracing)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                      device Probe*                             probeData               [[buffer(BufferIndexProbeData)]],
                             texture2d<float, access::sample>   minMaxTexture           [[texture(TextureIndexMinMaxDepth)]],
                             uint2                              tid                     [[thread_position_in_grid]]) {
    
    if (tid.x >= rayTracingTexture.get_width() || tid.y >= rayTracingTexture.get_height()) {
        return;
    }
    
    float2 pixel = float2(tid);
    float2 grid_size = float2(frameData.framebuffer_width, frameData.framebuffer_height);
    float2 uv = (pixel + 0.5f) / float2(frameData.framebuffer_width, frameData.framebuffer_height);
    float2 ndc = uv * 2.0f - 1.0f;
    ndc.y = -ndc.y;

//    float4 viewSpace = frameData.projection_matrix_inverse * float4(ndc, 1.0f, 1.0f);
//    viewSpace = viewSpace / viewSpace.w;
//
//    ray ray;
//    ray.origin = frameData.cameraPosition.xyz;
//    ray.direction = normalize(viewSpace.xyz);
//
//    ray.direction = normalize(ray.direction.x * frameData.cameraRight.xyz +
//                              ray.direction.y * frameData.cameraUp.xyz +
//                             -ray.direction.z * frameData.cameraForward.xyz);
//    
//    ray.min_distance = 0.001f;
//    ray.max_distance = INFINITY;
//    
//    // Perform intersection
//    intersector<triangle_data> intersector;
//    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);
//    
//    float3 color = 0.0f;
//    if (result.type != intersection_type::none) {
//        
//        unsigned int primitiveIndex = result.primitive_id;
//
//        // Barycentric interpolation for normal
//        float2 barycentrics = result.triangle_barycentric_coord;
//        
//        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];
//
//        float3 normal = normalize(triangle.normals[0].xyz * (1.0 - barycentrics.x - barycentrics.y) +
//                                  triangle.normals[1].xyz * barycentrics.x +
//                                  triangle.normals[2].xyz * barycentrics.y);
//
//        color = normal*0.5+0.5;
//    }

    constexpr int TILE_SIZE = 8;
    uint2 tileCount     = uint2(grid_size) / TILE_SIZE;
    uint2 tileID        = tid / TILE_SIZE;
    uint2 pixelInTile   = tid % TILE_SIZE;
    float probeDepth    = 0.0f;
    float3 worldPos     = float3(0.0);

    // Only process at tile centers
    if (pixelInTile.x == 4 && pixelInTile.y == 4) {
        uint probeIndex = tileID.y * tileCount.x + tileID.x;
        
        if (probeIndex < (100 * 75)) {
            float2 minMaxDepth = minMaxTexture.sample(depthSampler, uv, level(0)).xy;
            probeDepth = minMaxDepth.y; // Use max depth
            
            worldPos = reconstructWorldPosition(ndc, probeDepth,
                                                    frameData.projection_matrix_inverse,
                                                    frameData.inverse_view_matrix);
            
//            float3 r = ray.origin + ray.direction * result.distance;
            probeData[probeIndex].position = float4(worldPos, 1.0f);
        }
    }
    
    rayTracingTexture.write(float4(probeDepth, probeDepth, probeDepth, 1.0), tid);
}
