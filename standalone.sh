#!/bin/bash

# Define the build directory
BUILD_DIR="build"

# Create the build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Navigate to the build directory
cd "$BUILD_DIR" || exit

# Run CMake to configure the project
cmake ..

# Build the project using the maximum number of available processors
cmake --build . -- -j$(sysctl -n hw.ncpu)

./metallagmenos
