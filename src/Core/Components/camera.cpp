#include "camera.hpp"

void Camera::updateCameraVectors() {
    simd::float3 newFront;
    newFront.x = cos(yaw * M_PI / 180.0f) * cos(pitch * M_PI / 180.0f);
    newFront.y = sin(pitch * M_PI / 180.0f);
    newFront.z = sin(yaw * M_PI / 180.0f) * cos(pitch * M_PI / 180.0f);
    
    front = simd::normalize(newFront);
    right = simd::normalize(simd::cross(front, worldUp));
    up = simd::normalize(simd::cross(right, front));
}

void Camera::processKeyboardInput(GLFWwindow* window, float deltaTime) {
    float velocity = movementSpeed * deltaTime;
    
    if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS)
        position += front * velocity;
    if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS)
        position -= front * velocity;
    if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS)
        position -= right * velocity;
    if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS)
        position += right * velocity;
    if (glfwGetKey(window, GLFW_KEY_E) == GLFW_PRESS)
        position += up * velocity;
    if (glfwGetKey(window, GLFW_KEY_Q) == GLFW_PRESS)
        position -= up * velocity;
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);
}


void Camera::processMouseButton(GLFWwindow* window, int button, int action) {
    if (button == GLFW_MOUSE_BUTTON_LEFT) {
        if (action == GLFW_PRESS) {
            isDragging = true;

            // Store the current cursor position as the last position
            glfwGetCursorPos(window, &lastX, &lastY);
        } else if (action == GLFW_RELEASE) {
            isDragging = false;
        }
    }
}

void Camera::processMouseMovement(float xpos, float ypos) {
    if (!isDragging) return;
    
    float xoffset = xpos - lastX;
    float yoffset = lastY - ypos;
    lastX = xpos;
    lastY = ypos;
    
    xoffset *= mouseSensitivity;
    yoffset *= mouseSensitivity;
    
    yaw += xoffset;
    pitch += yoffset;
    
    if (pitch > 89.0f)
        pitch = 89.0f;
    if (pitch < -89.0f)
        pitch = -89.0f;
        
    updateCameraVectors();
}