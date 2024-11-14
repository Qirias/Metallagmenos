#include <simd/simd.h>

struct FrameData {
	// Per Frame Constants
	simd::float4x4 projection_matrix;                // 16 bytes (Total: 16 bytes)
	simd::float4x4 projection_matrix_inverse;         // 16 bytes (Total: 32 bytes)
	simd::float4x4 view_matrix;                       // 16 bytes (Total: 48 bytes)
	uint framebuffer_width;                           // 4 bytes (Total: 52 bytes)
	uint framebuffer_height;                          // 4 bytes (Total: 56 bytes)

	simd::float4 sun_color;                           // 16 bytes (Total: 72 bytes)
	simd::float4 sun_eye_direction;                   // 16 bytes (Total: 88 bytes)
	float sun_specular_intensity;                     // 4 bytes (Total: 92 bytes)

	// Shadow matrices
	simd::float4x4 shadow_mvp_matrix;                 // 16 bytes (Total: 108 bytes)
	simd::float4x4 shadow_mvp_xform_matrix;           // 16 bytes (Total: 124 bytes)

	simd::float4x4 sky_modelview_matrix;              // 16 bytes (Total: 140 bytes)

	// Padding (if required for alignment)
	 uint padding;                                   // 4 bytes (Total: 144 bytes)
};

struct ShadowVertex
{
    simd::float4 position;
};

typedef enum RenderTargetIndex
{
	RenderTargetLighting  = 0,
	RenderTargetAlbedo    = 1,
	RenderTargetNormal    = 2,
	RenderTargetDepth     = 3
} RenderTargetIndex;

typedef enum VertexAttributes
{
	VertexAttributePosition  = 0,
	VertexAttributeTexcoord  = 1,
	VertexAttributeNormal    = 2,
	VertexAttributeTangent   = 3,
	VertexAttributeBitangent = 4
} VertexAttributes;
