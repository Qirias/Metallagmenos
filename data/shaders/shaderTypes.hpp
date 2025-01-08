#include <simd/simd.h>

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
