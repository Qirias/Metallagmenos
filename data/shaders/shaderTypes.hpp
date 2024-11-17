#include <simd/simd.h>
#include "config.hpp"

struct FrameData {
	// Per Frame Constants
	simd::float4x4 projection_matrix;            // 64 bytes (offset: 0)
	simd::float4x4 projection_matrix_inverse;    // 64 bytes (offset: 64)
	simd::float4x4 view_matrix;                  // 64 bytes (offset: 128)
	
	// Group smaller scalars together to minimize padding
	uint framebuffer_width;                      // 4 bytes  (offset: 192)
	uint framebuffer_height;                     // 4 bytes  (offset: 196)
	float sun_specular_intensity;                // 4 bytes  (offset: 200)
	uint _pad1;                                  // 4 bytes  (offset: 204) - explicit padding for alignment
	
	// Vector group
	simd::float4 sun_color;                      // 16 bytes (offset: 208)
	simd::float4 sun_eye_direction;              // 16 bytes (offset: 224)
	
	// Matrix group
	simd::float4x4 shadow_mvp_matrix;            // 64 bytes (offset: 240)
	simd::float4x4 shadow_mvp_xform_matrix;      // 64 bytes (offset: 304)
	simd::float4x4 sky_modelview_matrix;         // 64 bytes (offset: 368)
	simd::float4x4 scene_model_matrix;           // 64 bytes (offset: 432)
	simd::float4x4 scene_modelview_matrix;       // 64 bytes (offset: 496)
	
	// Note: float3x3 is padded to float4x3 in GPU memory
	simd::float3x3 scene_normal_matrix;          // 48 bytes (offset: 560) - Each row padded to float4
	uint8_t _pad2[32];                           // 32 bytes padding to reach 640 bytes total
	
	simd::float4x4 	shadow_cascade_mvp_matrices[SHADOW_CASCADE_COUNT];
	simd::float4x4 	shadow_cascade_mvp_xform_matrices[SHADOW_CASCADE_COUNT];
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
	VertexAttributePosition  	= 0,
	VertexAttributeTexcoord  	= 1,
	VertexAttributeNormal    	= 2,
	VertexAttributeTangent   	= 3,
	VertexAttributeBitangent 	= 4,
	VertexAttributeDiffuseIndex = 5,
	VertexAttributeNormalIndex 	= 6
} VertexAttributes;

typedef enum TextureIndex
{
	TextureIndexBaseColor = 0,
	TextureIndexSpecular  = 1,
	TextureIndexNormal    = 2,
	TextureIndexShadow    = 3,
	TextureIndexAlpha     = 4,

	NumMeshTextures = TextureIndexNormal + 1

} TextureIndex;
