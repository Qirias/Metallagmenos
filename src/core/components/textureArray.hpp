//
//  TextureArray.hpp
//  Metal-Tutorial
//

#pragma once
#include <Metal/Metal.hpp>
#include <stb/stb_image.h>
#include <vector>

#include "vertexData.hpp"

enum TextureType {
    DIFFUSE,
    NORMAL,
    SPECULAR,
};

class TextureArray {
public:
    TextureArray(std::vector<std::string>& FilePaths,
                 MTL::Device* metalDevice, TextureType type);
    ~TextureArray();
    
    void loadTextures(std::vector<std::string>& filePaths,
                      TextureType type);
    
    MTL::Texture* diffuseTextureArray;
    std::vector<TextureInfo> diffuseTextureInfos;
	
	MTL::Texture* normalTextureArray;
	std::vector<TextureInfo> normalTextureInfos;

private:
    MTL::Device* device;
};
