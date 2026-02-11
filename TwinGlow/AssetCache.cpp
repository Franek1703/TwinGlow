#include "AssetCache.h"
#include <ArduinoJson.h>

AssetCache::AssetCache() {
}

AssetCache::~AssetCache() {
    clear();
}

bool AssetCache::addAsset(const CachedAsset& asset) {
    // Remove existing if present
    removeAsset(asset.id);
    
    // Add new asset
    assets.push_back(asset);
    
    Serial.print(F("[AssetCache] Added asset: "));
    Serial.println(asset.id);
    return true;
}

bool AssetCache::removeAsset(const String& assetId) {
    for (auto it = assets.begin(); it != assets.end(); ++it) {
        if (it->id == assetId) {
            assets.erase(it);
            Serial.print(F("[AssetCache] Removed asset: "));
            Serial.println(assetId);
            return true;
        }
    }
    return false;
}

void AssetCache::clear() {
    assets.clear();
    Serial.println(F("[AssetCache] Cleared"));
}

CachedAsset* AssetCache::getAsset(const String& assetId) {
    for (auto& asset : assets) {
        if (asset.id == assetId) {
            return &asset;
        }
    }
    return nullptr;
}

bool AssetCache::parseAsset(const String& assetId, const String& jsonStr, CachedAsset& asset) {
    asset.id = assetId;
    asset.pixels.clear();
    asset.basePixels.clear();
    asset.frames.clear();
    
    DynamicJsonDocument doc(8192); // Adjust size as needed
    DeserializationError error = deserializeJson(doc, jsonStr);
    
    if (error) {
        Serial.print(F("[AssetCache] JSON parse error: "));
        Serial.println(error.c_str());
        return false;
    }
    
    // Parse type
    if (doc.containsKey("type")) {
        asset.type = doc["type"].as<String>();
    }
    
    // Parse encoding
    if (doc.containsKey("encoding")) {
        asset.encoding = doc["encoding"].as<String>();
    }
    
    // Parse based on encoding
    if (asset.encoding == "SPARSE_I16_RGB888") {
        if (doc.containsKey("pixels")) {
            JsonArray pixelsArray = doc["pixels"];
            for (JsonArray pixelArray : pixelsArray) {
                if (pixelArray.size() >= 2) {
                    Pixel pixel;
                    pixel.index = pixelArray[0].as<uint8_t>();
                    pixel.color = pixelArray[1].as<uint32_t>();
                    asset.pixels.push_back(pixel);
                }
            }
        }
    } else if (asset.encoding == "DELTA_SPARSE_I16_RGB888") {
        // Parse basePixels
        if (doc.containsKey("basePixels")) {
            JsonArray baseArray = doc["basePixels"];
            for (JsonArray pixelArray : baseArray) {
                if (pixelArray.size() >= 2) {
                    Pixel pixel;
                    pixel.index = pixelArray[0].as<uint8_t>();
                    pixel.color = pixelArray[1].as<uint32_t>();
                    asset.basePixels.push_back(pixel);
                }
            }
        }
        
        // Parse frames
        if (doc.containsKey("frames")) {
            JsonArray framesArray = doc["frames"];
            for (JsonObject frameObj : framesArray) {
                AnimationFrame frame;
                frame.delayMs = frameObj["delayMs"].as<uint16_t>();
                
                if (frameObj.containsKey("pixels")) {
                    JsonArray pixelsArray = frameObj["pixels"];
                    for (JsonArray pixelArray : pixelsArray) {
                        if (pixelArray.size() >= 2) {
                            Pixel pixel;
                            pixel.index = pixelArray[0].as<uint8_t>();
                            pixel.color = pixelArray[1].as<uint32_t>();
                            frame.pixels.push_back(pixel);
                        }
                    }
                }
                
                asset.frames.push_back(frame);
            }
        }
        
        // Parse loop
        if (doc.containsKey("loop")) {
            asset.loop = doc["loop"].as<bool>();
        }
    }
    
    return true;
}

bool AssetCache::parseSparsePixels(const String& jsonStr, std::vector<Pixel>& pixels) {
    // This is handled in parseAsset
    return true;
}

bool AssetCache::parseDeltaFrames(const String& jsonStr, std::vector<Pixel>& basePixels, std::vector<AnimationFrame>& frames) {
    // This is handled in parseAsset
    return true;
}
