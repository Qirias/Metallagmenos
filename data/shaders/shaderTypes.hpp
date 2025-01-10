#include <simd/simd.h>

struct FrameData {
    // Per Frame Constants
    simd::float4x4 projection_matrix;            // 64 bytes (offset: 0)
    simd::float4x4 projection_matrix_inverse;    // 64 bytes (offset: 64)
    simd::float4x4 view_matrix;                  // 64 bytes (offset: 128)

    // Camera properties (aligned to 16 bytes)
    simd::float4 cameraUp;                       // 16 bytes (offset: 192)
    simd::float4 cameraRight;                    // 16 bytes (offset: 208)
    simd::float4 cameraForward;                  // 16 bytes (offset: 224)
    simd::float4 cameraPosition;                 // 16 bytes (offset: 240)

    uint framebuffer_width;                      // 4 bytes  (offset: 256)
    uint framebuffer_height;                     // 4 bytes  (offset: 260)
    float sun_specular_intensity;                // 4 bytes  (offset: 264)
    size_t resourcesStride;                        // 4 bytes  (offset: 268)

    // Sun properties (aligned to 16 bytes)
    simd::float4 sun_color;                      // 16 bytes (offset: 272)
    simd::float4 sun_eye_direction;              // 16 bytes (offset: 288)
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

typedef enum BufferIndex {
    BufferIndexFrameData = 0,
    BufferIndexResources = 1,
    BufferIndexAccelerationStructure = 2,
    BufferIndexOutputTexture = 3
} BufferIndex;
