#define METAL
#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

#include "vertexData.hpp"
#include "shaderTypes.hpp"

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

struct MeshResources {
    device float3* vertexNormals;
    device uint* indices;
};

vertex VertexOut vertex_function(uint       vertexID    [[vertex_id]],
                        constant FrameData& frameData   [[buffer(BufferIndexFrameData)]]) {
    VertexOut out;

    // Generate full-screen triangle
    float2 position = float2((vertexID << 1) & 2, vertexID & 2);
    out.position    = float4(position * float2(2, -2) + float2(-1, 1), 0.0f, 1.0f);
    out.texCoords   = position;

    return out;
}

fragment float4 fragment_function(VertexOut         in  [[stage_in]],
                                  texture2d<float>  tex [[texture(0)]]) {
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);

    float3 color = tex.sample(sam, in.texCoords).xyz;

    return float4(color, 1.0f);
}

kernel void raytracingKernel(texture2d<float, access::write>    outputTexture           [[texture(0)]],
                    constant FrameData&                         frameData               [[buffer(BufferIndexFrameData)]],
                             primitive_acceleration_structure   accelerationStructure   [[buffer(BufferIndexAccelerationStructure)]],
                             device MeshResources*              resources               [[buffer(BufferIndexResources)]],
                             uint2                              tid                     [[thread_position_in_grid]]) {
    if (tid.x >= outputTexture.get_width() || tid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 pixel = float2(tid);
    float2 uv = (pixel) / float2(frameData.framebuffer_width, frameData.framebuffer_height);
    uv = uv * 2.0f  - 1.0f;
    uv.y = -uv.y;

    ray ray;
    ray.origin = frameData.cameraPosition.xyz;
    ray.direction = normalize(uv.x * frameData.cameraRight.xyz + uv.y * frameData.cameraUp.xyz + frameData.cameraForward.xyz);
    ray.min_distance = 0.001f;
    ray.max_distance = INFINITY;
    
    intersector<triangle_data> intersector;
    intersection_result<triangle_data> result = intersector.intersect(ray, accelerationStructure);
      
    float3 color = 0.0f;
    if (result.type != intersection_type::none) {
        
        unsigned int primitiveIndex = result.primitive_id;
        unsigned int geometryIndex = result.geometry_id;

        uint3 indices = uint3(
            resources[geometryIndex].indices[primitiveIndex * 3],
            resources[geometryIndex].indices[primitiveIndex * 3 + 1],
            resources[geometryIndex].indices[primitiveIndex * 3 + 2]
        );

        float3 n0 = resources[geometryIndex].vertexNormals[indices.x];
        float3 n1 = resources[geometryIndex].vertexNormals[indices.y];
        float3 n2 = resources[geometryIndex].vertexNormals[indices.z];

        float2 barycentrics = result.triangle_barycentric_coord;
        float3 normal = normalize(
            n0 * (1.0 - barycentrics.x - barycentrics.y) +
            n1 * barycentrics.x +
            n2 * barycentrics.y
        );

        float3 lightDir = normalize(-frameData.sun_eye_direction.xyz);
        float diffuse = max(0.0f, dot(normal, lightDir));

        float3 ambient = float3(0.1);
        float3 sunLight = frameData.sun_color.xyz * diffuse;

        color = (ambient + sunLight) * float3(0.7);
//        color = (normal*0.5)+0.5;
        color = float3(barycentrics.x, barycentrics.y, 1.0);
    }

        outputTexture.write(float4(color, 1.0), tid);
}
