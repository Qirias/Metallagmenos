#define METAL
#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

#include "vertexData.hpp"
#include "shaderTypes.hpp"

struct TriangleResources {
    struct TriangleData {
        float4 normals[3];
        float4 colors[3];
    };
    device TriangleData* triangles;
};

kernel void raytracingKernel(texture2d<float, access::write>    rayTracingTexture       [[texture(TextureIndexRaytracing)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                const device TriangleResources::TriangleData*   resources               [[buffer(BufferIndexResources)]],
                             uint2                              tid                     [[thread_position_in_grid]]) {
    
    if (tid.x >= rayTracingTexture.get_width() || tid.y >= rayTracingTexture.get_height()) {
        return;
    }
    
    float2 pixel = float2(tid);
    float2 uv = (pixel + 0.5f) / float2(frameData.framebuffer_width, frameData.framebuffer_height);
    float2 ndc = uv * 2.0f - 1.0f;
    ndc.y = -ndc.y;

    float4 viewSpace = frameData.projection_matrix_inverse * float4(ndc, 1.0f, 1.0f);
    viewSpace = viewSpace / viewSpace.w;

    ray ray;
    ray.origin = frameData.cameraPosition.xyz;
    ray.direction = normalize(viewSpace.xyz);

    ray.direction = normalize(ray.direction.x * frameData.cameraRight.xyz +
                              ray.direction.y * frameData.cameraUp.xyz +
                             -ray.direction.z * frameData.cameraForward.xyz);
    
    ray.min_distance = 0.001f;
    ray.max_distance = INFINITY;
    
    // Perform intersection
    intersector<triangle_data> intersector;
    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);
    
    float3 color = 0.0f;
    if (result.type != intersection_type::none) {
        
        unsigned int primitiveIndex = result.primitive_id;

        // Barycentric interpolation for normal
        float2 barycentrics = result.triangle_barycentric_coord;
        
        const device TriangleResources::TriangleData& triangle = resources[primitiveIndex];

        float3 normal = normalize(triangle.normals[0].xyz * (1.0 - barycentrics.x - barycentrics.y) +
                                  triangle.normals[1].xyz * barycentrics.x +
                                  triangle.normals[2].xyz * barycentrics.y);

        color = normal*0.5+0.5;
    }

    rayTracingTexture.write(float4(color, 1.0), tid);
}
