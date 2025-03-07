#include "sceneParser.hpp"
#include "mesh.hpp"
#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

SceneParser::SceneParser(MTL::Device* device, MTL::VertexDescriptor* vertexDescriptor)
    : metalDevice(device), defaultVertexDescriptor(vertexDescriptor) {
}

SceneParser::~SceneParser() {
}

std::vector<Mesh*> SceneParser::loadScene(const std::string& jsonFilePath) {
    std::vector<Mesh*> meshes;
    
    // Read the JSON file
    std::ifstream file(jsonFilePath);
    if (!file.is_open()) {
        std::cerr << "Failed to open scene file: " << jsonFilePath << std::endl;
        return meshes;
    }
    
    json sceneData;
    try {
        file >> sceneData;
    } catch (const json::parse_error& e) {
        std::cerr << "JSON parse error: " << e.what() << std::endl;
        file.close();
        return meshes;
    }
    file.close();
    
    std::unordered_map<std::string, std::string> meshPaths;
    
    if (sceneData["scene"].contains("meshes") && sceneData["scene"]["meshes"].is_array()) {
        for (const auto& meshDef : sceneData["scene"]["meshes"]) {
            if (meshDef.contains("name") && meshDef.contains("filename")) {
                std::string name = meshDef["name"];
                std::string filename = meshDef["filename"];

                std::string resolvedPath = processPath(filename);
                meshPaths[name] = resolvedPath;
            }
        }
    }
    
    // Load object instances
    if (sceneData["scene"].contains("objects") && sceneData["scene"]["objects"].is_array()) {
        for (const auto& objDef : sceneData["scene"]["objects"]) {
            if (!objDef.contains("mesh")) {
                std::cerr << "Object missing mesh reference, skipping" << std::endl;
                continue;
            }
            
            std::string meshName = objDef["mesh"];
            
            // Find the referenced mesh path
            if (meshPaths.find(meshName) == meshPaths.end()) {
                std::cerr << "Mesh not found: " << meshName << ", skipping object" << std::endl;
                continue;
            }
            
            try {
                // Create mesh info for this instance
                MeshInfo info;
                info.hasTextures = false; // Default to false
                
                // Parse position
                if (objDef.contains("pos") && objDef["pos"].is_array() && objDef["pos"].size() == 3) {
                    info.position = {
                        objDef["pos"][0],
                        objDef["pos"][1],
                        objDef["pos"][2]
                    };
                }
                
                // Parse scale
                if (objDef.contains("scale") && objDef["scale"].is_array() && objDef["scale"].size() == 3) {
                    info.scale = {
                        objDef["scale"][0],
                        objDef["scale"][1],
                        objDef["scale"][2]
                    };
                }
                
                // Parse color - check for both color and albedoColor for compatibility
                if (objDef.contains("color") && objDef["color"].is_array() && objDef["color"].size() == 3) {
                    info.color = {
                        objDef["color"][0],
                        objDef["color"][1],
                        objDef["color"][2]
                    };
                } else if (objDef.contains("albedoColor") && objDef["albedoColor"].is_array() && objDef["albedoColor"].size() == 3) {
                    info.color = {
                        objDef["albedoColor"][0],
                        objDef["albedoColor"][1],
                        objDef["albedoColor"][2]
                    };
                }
                
                // Parse has textures flag
                if (objDef.contains("hasTextures")) {
                    info.hasTextures = objDef["hasTextures"];
                }
                
                // Parse emissive properties
                if (objDef.contains("isEmissive")) {
                    info.isEmissive = objDef["isEmissive"];
                    
                    // If the object is emissive, parse the emissive color
                    if (info.isEmissive && objDef.contains("emissiveColor") && 
                        objDef["emissiveColor"].is_array() && objDef["emissiveColor"].size() == 3) {
                        info.emissiveColor = {
                            objDef["emissiveColor"][0],
                            objDef["emissiveColor"][1],
                            objDef["emissiveColor"][2]
                        };

                    } else if (info.isEmissive) {
                        // Default emissive color if not specified
                        info.emissiveColor = {1.0f, 1.0f, 1.0f};
                    }
                }
                
                std::string meshPath = meshPaths[meshName];
                Mesh* newMesh = new Mesh(meshPath.c_str(), metalDevice, defaultVertexDescriptor, info);
                
                newMesh->defaultVertexAttributes();
                
                meshes.push_back(newMesh);
            } catch (const std::exception& e) {
                std::cerr << "Error creating mesh '" << meshName << "': " << e.what() << std::endl;
            }
        }
    }
    
    return meshes;
}

std::string SceneParser::expandPathMacros(const std::string& path) {
    // Check for @MODELS_PATH@ macro
    std::string expandedPath = path;
    
    const std::string modelsPathMacro = "@MODELS_PATH@";
    size_t modelsPos = expandedPath.find(modelsPathMacro);
    if (modelsPos != std::string::npos) {
        expandedPath.replace(modelsPos, modelsPathMacro.length(), MODELS_PATH);
    }
    
    // Check for @SCENES_PATH@ macro
    const std::string scenesPathMacro = "@SCENES_PATH@";
    size_t scenesPos = expandedPath.find(scenesPathMacro);
    if (scenesPos != std::string::npos) {
        expandedPath.replace(scenesPos, scenesPathMacro.length(), SCENES_PATH);
    }
    
    // Check for @TEXTURE_PATH@ macro
    const std::string texturePathMacro = "@TEXTURE_PATH@";
    size_t texturePos = expandedPath.find(texturePathMacro);
    if (texturePos != std::string::npos) {
        expandedPath.replace(texturePos, texturePathMacro.length(), TEXTURE_PATH);
    }
    
    return expandedPath;
}

std::string SceneParser::processPath(const std::string& originalPath) {
    std::string expandedPath = expandPathMacros(originalPath);
    
    // Check if the expanded path exists directly
    std::ifstream fileCheck(expandedPath);
    if (fileCheck.good()) {
        fileCheck.close();
        return expandedPath;
    }
    fileCheck.close();
    
    // If not found, try common alternatives
    // 1. Try with MODELS_PATH prefix if it's not already there
    if (expandedPath.find(MODELS_PATH) == std::string::npos) {
        std::string modelPath = std::string(MODELS_PATH) + "/" + expandedPath;
        fileCheck.open(modelPath);
        if (fileCheck.good()) {
            fileCheck.close();
            return modelPath;
        }
        fileCheck.close();
    }

    return expandedPath;
}
