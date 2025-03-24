#include <simd/simd.h>

// Raster order group definitions
#define LightingROG  0
#define GBufferROG   1

struct GBufferData
{
    half4 lighting        [[color(RenderTargetLighting), raster_order_group(LightingROG)]];
    half4 albedo_specular [[color(RenderTargetAlbedo),   raster_order_group(GBufferROG)]];
    half4 normal_map      [[color(RenderTargetNormal),   raster_order_group(GBufferROG)]];
    float depth           [[color(RenderTargetDepth),    raster_order_group(GBufferROG)]];
};

// Final buffer outputs using Raster Order Groups
struct AccumLightBuffer
{
	half4 lighting [[color(RenderTargetLighting), raster_order_group(LightingROG)]];
};

constexpr sampler depthSampler(coord::normalized, filter::linear, mip_filter::linear);

constexpr sampler samplerLinear(s_address::clamp_to_zero,
                                t_address::clamp_to_zero,
                                r_address::clamp_to_zero,
                                mag_filter::linear,
                                min_filter::linear);

constexpr sampler samplerNearest(s_address::clamp_to_zero,
                                 t_address::clamp_to_zero,
                                 r_address::clamp_to_zero,
                                 mag_filter::nearest,
                                 min_filter::nearest);

constexpr sampler samplerPoint(mip_filter::none, filter::nearest);

constant float TWO_PI = 6.28318530718f;
constant float PI = 3.14159265359f;
