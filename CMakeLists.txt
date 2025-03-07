cmake_minimum_required(VERSION 3.15)

if(STANDALONE_BUILD)
    project(Metallagmenos LANGUAGES CXX OBJCXX)
elseif(XCODE_BUILD)
    project(Metallagmenos)
else()
    message(STATUS "Unknown build mode")
endif()

# Set C++ standard
set(CMAKE_CXX_STANDARD 20)

# Group sources into virtual folders for Xcode
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

set(IMGUI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/imgui")
set(IMGUI_SOURCES
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_glfw.cpp
    ${IMGUI_DIR}/backends/imgui_impl_metal.mm
)

# Set properties for Objective-C++ files
set_source_files_properties(
    ${IMGUI_DIR}/backends/imgui_impl_metal.mm
    PROPERTIES
    COMPILE_FLAGS "-x objective-c++"
    LANGUAGE OBJCXX
)

# Glob all source files in src and libs
file(GLOB_RECURSE SOURCES 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp" 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.hpp" 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.mm" 
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/*.mm"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/*.cc"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/*.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/shaders/*.hpp"
)

# Group sources into virtual folders for Xcode
source_group(TREE ${CMAKE_CURRENT_SOURCE_DIR} FILES ${SOURCES})

# Find all Metal shader files
file(GLOB SHADER_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/data/shaders/*.metal")

# Set texture path as a definition
add_definitions(-DTEXTURE_PATH="${CMAKE_CURRENT_SOURCE_DIR}/data/textures")
add_definitions(-DMODELS_PATH="${CMAKE_CURRENT_SOURCE_DIR}/data/models")
add_definitions(-DSCENES_PATH="${CMAKE_CURRENT_SOURCE_DIR}/data/scenes")


# tiny_glTF doesn't need to compile stb_image again
add_definitions(-DTINYGLTF_NO_STB_IMAGE -DTINYGLTF_NO_STB_IMAGE_WRITE)
add_definitions(-DIMGUI_IMPL_METAL_CPP)

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
                -I ${CMAKE_CURRENT_SOURCE_DIR}/src/core
        DEPENDS ${SHADER_SOURCE}  # Add each shader source as a dependency
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
    DEPENDS ${SHADER_OUTPUTS}  # Ensure it depends on all AIR files
    COMMENT "Creating metallib from AIR files"
)

# Add custom target for shader compilation
add_custom_target(shaders DEPENDS ${SHADER_METALLIB} ${SHADER_SOURCES})
set_target_properties(shaders PROPERTIES FOLDER "Hidden")

# Add the executable target
add_executable(${PROJECT_NAME} ${SOURCES} ${SHADER_SOURCES})

# Check if it's a standalone build or an Xcode build
if(DEFINED STANDALONE_BUILD)
    message(STATUS "Building as standalone")
    set_target_properties(${PROJECT_NAME} PROPERTIES
        MACOSX_BUNDLE FALSE   
        XCODE_GENERATE_SCHEME FALSE
    )
elseif(DEFINED XCODE_BUILD)
    message(STATUS "Building with Xcode")
    set_target_properties(${PROJECT_NAME} PROPERTIES
        MACOSX_BUNDLE TRUE 
        XCODE_GENERATE_SCHEME TRUE
        XCODE_SCHEME_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        XCODE_SCHEME_LAUNCH_MODE "0"  # Prevent multiple executables
    )
else()
    message(STATUS "Unknown build mode")
endif()

# Set the Xcode specific attributes
set_target_properties(${PROJECT_NAME} PROPERTIES
    XCODE_GENERATE_SCHEME TRUE
    XCODE_SCHEME_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

# Make sure shaders are built before the main target
add_dependencies(${PROJECT_NAME} shaders)

# Set properties to treat .mm files as Objective-C++
set_source_files_properties(src/core/engine.mm PROPERTIES LANGUAGE CXX)
set_source_files_properties(src/main.mm PROPERTIES LANGUAGE CXX)

# Link the METAL_CPP library
target_link_libraries(${PROJECT_NAME} PRIVATE METAL_CPP)

# Include directories for Metal-CPP headers and your project headers
target_include_directories(${PROJECT_NAME} PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/metal-cmake/metal-cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/math
    ${CMAKE_CURRENT_SOURCE_DIR}/src/editor
    ${CMAKE_CURRENT_SOURCE_DIR}/external
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
)

# Link the GLFW library
target_link_libraries(${PROJECT_NAME} PRIVATE "${GLFW_LIBRARY_PATH}")

# Hide CMake targets from Xcode
set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "Hidden")