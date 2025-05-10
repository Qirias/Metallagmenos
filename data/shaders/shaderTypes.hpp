#include <simd/simd.h>
#include "config.hpp"

struct FrameData {
	// Per Frame Constants
	simd::float4x4 projection_matrix;
	simd::float4x4 projection_matrix_inverse;
	simd::float4x4 view_matrix;
    simd::float4x4 view_matrix_inverse;
    
    // Camera properties
    simd::float4 cameraUp;
    simd::float4 cameraRight;
    simd::float4 cameraForward;
    simd::float4 cameraPosition;
	
	uint framebuffer_width;
	uint framebuffer_height;
	float sun_specular_intensity;
    float near_plane;
    float far_plane;
    float frameNumber;
    float temporalAccumulationCount;
    float maxTemporalAccumulationFrames;
	
	// Vector group
	simd::float4 sun_color;
	simd::float4 sun_eye_direction;
	
	// Matrix group
	simd::float4x4 prev_projection_matrix;
    simd::float4x4 prev_view_matrix;
    simd::float4x4 prev_projection_matrix_inverse;
    simd::float4x4 prev_view_matrix_inverse;
	simd::float4x4 scene_model_matrix;
	simd::float4x4 scene_modelview_matrix;
	
	// Note: float3x3 is padded to float4x3 in GPU memory
	simd::float3x3 scene_normal_matrix;          // 48 bytes
};

struct CascadeData {
    uint cascadeLevel;
    uint maxCascade;
    uint probeSpacing;
    float intervalLength;
    float enableSky;
    float enableSun;
    float enableTA;
    uint _pad;
};

struct Probe {
    simd::float4 position;
};

struct ProbeRay {
    simd::float4 intervalStart;
    simd::float4 intervalEnd;
    simd::float4 color;
};

struct ProbeAccum {
    float temporalAccumulationCount;
    bool isHistoryValid;
    char _pad[3];
};

typedef enum RenderTargetIndex {
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
	TextureIndexBaseColor 			= 0,
	TextureIndexSpecular  			= 1,
	TextureIndexNormal    			= 2,
	TextureIndexAlpha     			= 3,
    TextureIndexRadiance 			= 4,
    TextureIndexRadianceUpper       = 5,
    TextureIndexDepthTexture		= 6,
    TextureIndexHistoryDepthTexture = 7,
    TextureIndexUpperRadiance       = 8,
    TextureIndexHistory             = 9,

	NumMeshTextures = TextureIndexNormal + 1

} TextureIndex;

typedef enum BufferIndex {
    BufferIndexVertexData               = 0,
    BufferIndexVertexBytes              = 1,
    BufferIndexFrameData                = 2,
    BufferIndexResources                = 3,
    BufferIndexAccelerationStructure    = 4,
    BufferIndexDiffuseInfo             	= 5,
    BufferIndexNormalInfo              	= 6,
    BufferIndexProbeData                = 7,
    BufferIndexProbeRayData             = 8,
    BufferIndexCascadeData              = 9,
    BufferIndexProbeAccumData           = 10,
    BufferIndexColor       		    	= 11,
	BufferIndexIsEmissive				= 12,
} BufferIndex;
