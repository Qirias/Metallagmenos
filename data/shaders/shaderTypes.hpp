#include <simd/simd.h>
#include "config.hpp"

struct FrameData {
	// Per Frame Constants
	simd::float4x4 projection_matrix;
	simd::float4x4 projection_matrix_inverse;
	simd::float4x4 view_matrix;
    
    // Camera properties
    simd::float4 cameraUp;
    simd::float4 cameraRight;
    simd::float4 cameraForward;
    simd::float4 cameraPosition;
	
	uint framebuffer_width;
	uint framebuffer_height;
	float sun_specular_intensity;
    uint cascadeLevel;
	
	// Vector group
	simd::float4 sun_color;
	simd::float4 sun_eye_direction;
	
	// Matrix group
	simd::float4x4 _pad2;
	simd::float4x4 _pad3;
    simd::float4x4 inverse_view_matrix;
	simd::float4x4 scene_model_matrix;
	simd::float4x4 scene_modelview_matrix;
	
	// Note: float3x3 is padded to float4x3 in GPU memory
	simd::float3x3 scene_normal_matrix;          // 48 bytes
};

struct Probe {
    simd::float4 position;
};

typedef enum RenderTargetIndex {
	RenderTargetLighting,
	RenderTargetAlbedo,
	RenderTargetNormal,
	RenderTargetDepth,
	RenderTargetMax
} RenderTargetIndex;

typedef enum VertexAttributes {
	VertexAttributePosition  	= 0,
	VertexAttributeTexcoord  	= 1,
	VertexAttributeNormal    	= 2,
	VertexAttributeTangent   	= 3,
	VertexAttributeBitangent 	= 4,
	VertexAttributeDiffuseIndex = 5,
	VertexAttributeNormalIndex 	= 6
} VertexAttributes;

typedef enum TextureIndex {
	TextureIndexBaseColor = 0,
	TextureIndexSpecular  = 1,
	TextureIndexNormal    = 2,
	TextureIndexAlpha     = 3,
    TextureIndexRaytracing = 4,
    TextureIndexMinMaxDepth = 5,

	NumMeshTextures = TextureIndexNormal + 1

} TextureIndex;

typedef enum BufferIndex {
    BufferIndexVertexData               = 0,
    BufferIndexVertexBytes              = 1,
    BufferIndexFrameData                = 2,
    BufferIndexResources                = 3,
    BufferIndexAccelerationStructure    = 4,
    BufferIndexDiffuseInfo             = 5,
    BufferIndexNormalInfo              = 6,
    BufferIndexProbeData                = 7
} BufferIndex;
