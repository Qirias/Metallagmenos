#include <simd/simd.h>

// Raster order group definitions
#define LightingROG  0
#define GBufferROG   1

struct GBufferData
{
    half4 lighting        [[color(RenderTargetLighting), raster_order_group(LightingROG)]];
    half4 albedo_specular [[color(RenderTargetAlbedo),   raster_order_group(GBufferROG)]];
    half4 normal_shadow   [[color(RenderTargetNormal),   raster_order_group(GBufferROG)]];
    float depth           [[color(RenderTargetDepth),    raster_order_group(GBufferROG)]];
};
