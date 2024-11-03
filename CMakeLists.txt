cmake_minimum_required(VERSION 3.15)
project(Metallagmenos)

# Set C++ standard
set(CMAKE_CXX_STANDARD 20)

# Group sources into virtual folders for Xcode
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# Glob all source files in src and libs
file(GLOB_RECURSE SOURCES 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp" 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.hpp" 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.mm" 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/libs/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/libs/*.h"
)

# Group sources into virtual folders for Xcode
source_group(TREE ${CMAKE_CURRENT_SOURCE_DIR} FILES ${SOURCES})

# Find all Metal shader files
file(GLOB SHADER_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/data/shaders/*.metal")

# Set texture path as a definition
add_definitions(-DTEXTURE_PATH="${CMAKE_CURRENT_SOURCE_DIR}/data/textures")
add_definitions(-DMODELS_PATH="${CMAKE_CURRENT_SOURCE_DIR}/data/models")

# Create source groups for Xcode
source_group(TREE ${CMAKE_CURRENT_SOURCE_DIR} FILES ${SOURCES} ${SHADER_SOURCES})

# Add the metal-cmake subdirectory but hide it from IDE
add_subdirectory(metal-cmake EXCLUDE_FROM_ALL)

# Define paths for GLFW
set(GLFW_LIBRARY_PATH "${CMAKE_CURRENT_SOURCE_DIR}/bin/glfw/libglfw.3.3.dylib")

# Create output paths for each shader
set(SHADER_OUTPUTS)
foreach(SHADER_SOURCE ${SHADER_SOURCES})
    get_filename_component(SHADER_NAME ${SHADER_SOURCE} NAME_WE)
    set(SHADER_AIR "${CMAKE_CURRENT_BINARY_DIR}/${SHADER_NAME}.air")
    list(APPEND SHADER_OUTPUTS ${SHADER_AIR})
    
    # Compile Metal shader to AIR with include paths
    add_custom_command(
        OUTPUT ${SHADER_AIR}
        COMMAND xcrun -sdk macosx metal 
                -c ${SHADER_SOURCE} 
                -o ${SHADER_AIR}
                -I ${CMAKE_CURRENT_SOURCE_DIR}/src/Core
        DEPENDS ${SHADER_SOURCE} ${CMAKE_CURRENT_SOURCE_DIR}/src/Core/VertexData.hpp
        COMMENT "Compiling ${SHADER_NAME}.metal to AIR"
    )
endforeach()

# Set the final metallib path
set(SHADER_METALLIB "${CMAKE_CURRENT_BINARY_DIR}/default.metallib")
add_definitions(-DSHADER_METALLIB="${SHADER_METALLIB}")

# Create metallib from all AIR files
add_custom_command(
    OUTPUT ${SHADER_METALLIB}
    COMMAND xcrun -sdk macosx metallib ${SHADER_OUTPUTS} -o ${SHADER_METALLIB}
    DEPENDS ${SHADER_OUTPUTS}
    COMMENT "Creating metallib from AIR files"
)

# Add custom target for shader compilation
add_custom_target(shaders DEPENDS ${SHADER_METALLIB})
set_target_properties(shaders PROPERTIES FOLDER "Hidden")

# Add the executable target
add_executable(${PROJECT_NAME} ${SOURCES} ${SHADER_SOURCES})

# Set the Xcode specific attributes
set_target_properties(${PROJECT_NAME} PROPERTIES
    XCODE_GENERATE_SCHEME TRUE
    XCODE_SCHEME_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

# Make sure shaders are built before the main target
add_dependencies(${PROJECT_NAME} shaders)

# Set properties to treat .mm files as Objective-C++
set_source_files_properties(src/Core/engine.mm PROPERTIES LANGUAGE CXX)
set_source_files_properties(src/main.mm PROPERTIES LANGUAGE CXX)

# Link the METAL_CPP library
target_link_libraries(${PROJECT_NAME} PRIVATE METAL_CPP)

# Include directories for Metal-CPP headers and your project headers
target_include_directories(${PROJECT_NAME} PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/metal-cmake/metal-cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/Core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/Math
    ${CMAKE_CURRENT_SOURCE_DIR}/libs
)

# Link the GLFW library
target_link_libraries(${PROJECT_NAME} PRIVATE "${GLFW_LIBRARY_PATH}")

# Hide CMake targets from Xcode
set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "Hidden")