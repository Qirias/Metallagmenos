#pragma once

#include "../pch.hpp"

// Enum for all texture resources
enum class TextureName {
    // G-Buffer textures
    AlbedoGBuffer,
    NormalGBuffer,
    DepthGBuffer,
    
    // Depth textures
    DepthStencilTexture,
    ForwardDepthStencilTexture,
    LinearDepthTexture,
    MinMaxDepthTexture,
    
    // Ray tracing textures
    FinalGatherTexture,
    BlurredColorTexture,
    IntermediateBlurTexture,
    HistoryTexture
};

// Enum for buffer resources
enum class BufferName {
    TriangleResources
};

// Helper class to convert enums to strings
class ResourceNames {
public:
    static std::string toString(TextureName name) {
        static const std::unordered_map<TextureName, std::string> textureNames = {
            {TextureName::AlbedoGBuffer, "AlbedoGBuffer"},
            {TextureName::NormalGBuffer, "NormalGBuffer"},
            {TextureName::DepthGBuffer, "DepthGBuffer"},
            {TextureName::DepthStencilTexture, "DepthStencilTexture"},
            {TextureName::ForwardDepthStencilTexture, "ForwardDepthStencilTexture"},
            {TextureName::LinearDepthTexture, "LinearDepthTexture"},
            {TextureName::MinMaxDepthTexture, "MinMaxDepthTexture"},
            {TextureName::FinalGatherTexture, "FinalGatherTexture"},
            {TextureName::BlurredColorTexture, "BlurredColorTexture"},
            {TextureName::IntermediateBlurTexture, "IntermediateBlurTexture"},
            {TextureName::HistoryTexture, "HistoryTexture"}
        };
        
        auto it = textureNames.find(name);
        if (it != textureNames.end()) {
            return it->second;
        }
        
        return "UnknownTexture";
    }
    
    static std::string toString(BufferName name) {
        static const std::unordered_map<BufferName, std::string> bufferNames = {
            {BufferName::TriangleResources, "TriangleResourcesBuffer"}
        };
        
        auto it = bufferNames.find(name);
        if (it != bufferNames.end()) {
            return it->second;
        }
        
        return "UnknownBuffer";
    }
};
