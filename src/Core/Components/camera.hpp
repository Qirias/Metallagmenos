#pragma once
#include "pch.hpp"
#include "AAPLMathUtilities.h"
#include <GLFW/glfw3.h>

class Camera {
public:
    Camera(simd::float3 position = simd::float3{0.0f, 0.0f, 3.0f}) 
        : position(position)
        , worldUp(simd::float3{0.0f, 1.0f, 0.0f})
        , yaw(180.0f)
        , pitch(0.0f)
        , movementSpeed(5.0f)
        , mouseSensitivity(0.1f)
        , fov(45.0f)
        , isDragging(false) {
        updateCameraVectors();
    }
    
    void processKeyboardInput(GLFWwindow* window, float deltaTime);
    void processMouseButton(GLFWwindow* window, int button, int action);
    void processMouseMovement(float xpos, float ypos);
    
    matrix_float4x4 getViewMatrix() const {
        return matrix_look_at_right_hand(position, position + front, up);
    }
    
    matrix_float4x4 getProjectionMatrix(float aspectRatio) const {
        return matrix_perspective_right_hand(
            fov * (M_PI / 180.0f),
            aspectRatio,
            0.1f,
            400.0f
        );
    }
    
    
    simd::float3 position;
    simd::float3 front;
    simd::float3 up;
    simd::float3 right;
    simd::float3 worldUp;
    
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
