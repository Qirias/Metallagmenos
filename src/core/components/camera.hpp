#pragma once
#include "pch.hpp"
#include "AAPLMathUtilities.h"
#include <GLFW/glfw3.h>

class Camera {
public:
    Camera(simd::float3 position, float nearPlane, float farPlane)
        : position(position)
        , worldUp(simd::float3{0.0f, 1.0f, 0.0f})
		, nearPlane(nearPlane)
		, farPlane(farPlane)
        , yaw(-180.0f)
        , pitch(-35.0f)
        , movementSpeed(3.0f)
        , mouseSensitivity(0.1f)
        , fov(45.0f)
        , isDragging(false) {
        updateCameraVectors();
    }
    
    void processKeyboardInput(GLFWwindow* window, float deltaTime);
    void processMouseButton(GLFWwindow* window, int button, int action);
    void processMouseMovement(float xpos, float ypos);
    
	void setProjectionMatrix(float fovInDegrees, float aspectRatio, float nearPlane, float farPlane);
	void setViewMatrix() { viewMatrix = matrix_look_at_right_hand(position, position + front, up); }

	matrix_float4x4 getViewMatrix() const { return viewMatrix; }
    matrix_float4x4 getInverseViewMatrix() const { return simd::inverse(viewMatrix); }
	matrix_float4x4 getProjectionMatrix() const { return projectionMatrix; }
    
    simd::float3 getPosition() const { return position; }
    float getFov() const { return fov; }
	void setFrustumCornersWorldSpace(simd::float3* frustumCorners, float nearZ, float farZ);

public:
    simd::float3 position;
    simd::float3 front;
    simd::float3 up;
    simd::float3 right;
    simd::float3 worldUp;
	
	matrix_float4x4 projectionMatrix;
	matrix_float4x4 viewMatrix;
    
	float aspectRatio;
	float nearPlane;
	float farPlane;
	
    float yaw;
    float pitch;
    double lastX;
    double lastY;
    
    float movementSpeed;
    float mouseSensitivity;
    float fov;
    bool isDragging;
    
    void updateCameraVectors();
};
