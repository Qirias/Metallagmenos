cmake_minimum_required(VERSION 3.15)
project(Metallagmenos)

# Set C++ standard
set(CMAKE_CXX_STANDARD 20)

# Add the metal-cmake subdirectory
add_subdirectory(metal-cmake)

# Define the source files for your project
set(SOURCES
    src/main.mm  
    src/Core/engine.mm
    src/Core/pch.cpp
)

set(GLFW_LIBRARY_PATH "${CMAKE_CURRENT_SOURCE_DIR}/bin/glfw/libglfw.3.3.dylib")

# Add the executable target for your project
add_executable(${PROJECT_NAME} ${SOURCES})

# Set properties to treat .mm files as Objective-C++
set_source_files_properties(src/core/engine.mm PROPERTIES LANGUAGE CXX)

# Link the METAL_CPP library
target_link_libraries(${PROJECT_NAME} PRIVATE METAL_CPP)

# Include directories for Metal-CPP headers and your project headers
target_include_directories(${PROJECT_NAME} PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/metal-cmake/metal-cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/libs 
)

# Link the GLFW library
target_link_libraries(${PROJECT_NAME} PRIVATE "${GLFW_LIBRARY_PATH}")
