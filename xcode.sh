#!/bin/bash

# Define the build directory
BUILD_DIR="build_xcode"

# Create the build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Navigate to the build directory
cd "$BUILD_DIR" || exit

# Run CMake to configure the project with Xcode generator
cmake -G Xcode ..

# Inform the user that the Xcode project has been created
echo "Xcode project has been created in the '$BUILD_DIR' directory."
