#pragma once

#include <string>
#include <vector>
#include <unordered_map>

namespace MTL {
    class Device;
    class VertexDescriptor;
}

class Mesh;

class SceneParser {
public:
    SceneParser(MTL::Device* device, MTL::VertexDescriptor* vertexDescriptor);
    ~SceneParser();

    std::vector<Mesh*> loadScene(const std::string& jsonFilePath);
    std::string expandPathMacros(const std::string& path);
    std::string processPath(const std::string& originalPath);

private:
    MTL::Device* metalDevice;
    MTL::VertexDescriptor* defaultVertexDescriptor;
};