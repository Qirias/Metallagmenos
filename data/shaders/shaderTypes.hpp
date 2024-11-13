#include <simd/simd.h>

struct FrameData {
    // Per Frame Constants
    simd::float4x4 projection_matrix;
    simd::float4x4 projection_matrix_inverse;
    simd::float4x4 view_matrix;
    uint framebuffer_width;
    uint framebuffer_height;

    simd::float4 sunDirection;
    simd::float4 sunColor;
};