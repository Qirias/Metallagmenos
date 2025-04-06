#include <simd/simd.h>

struct GBufferData
{
    half4 albedo_specular [[color(RenderTargetAlbedo)]];
    half4 normal_map      [[color(RenderTargetNormal)]];
    float depth           [[color(RenderTargetDepth)]];
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

constant float TWO_PI = 6.28318530718f;
constant float PI = 3.14159265359f;
