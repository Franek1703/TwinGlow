#include "AssetCache.h"
#include <ArduinoJson.h>

// Parse SPARSE_PACKED_V1: fixed-width 8-char groups, "IIRRGGBB" per pixel.
// II = pixel index 0-255, RRGGBB = colour. No separators, so a whole image is
// one Firestore string field instead of one map per pixel. The old per-pixel
// encoding pushed the asset document to ~23KB, which the Firebase client
// cannot buffer without PSRAM - the fetch then returned an empty body with no
// error code and the screen rendered black.
static bool parsePackedPixels(const char* packed, std::vector<Pixel>& out) {
    if (packed == nullptr) return false;

    size_t len = strlen(packed);
    if (len == 0) {
        Serial.println(F("[AssetCache] pixelsPacked is empty"));
        return false;
    }
    if (len % 8 != 0) {
        Serial.print(F("[AssetCache] pixelsPacked length not a multiple of 8: "));
        Serial.println(len);
        return false;
    }

    out.reserve(len / 8);
    for (size_t i = 0; i < len; i += 8) {
        char idxHex[3] = {packed[i], packed[i + 1], 0};
        char colHex[7] = {packed[i + 2], packed[i + 3], packed[i + 4],
                          packed[i + 5], packed[i + 6], packed[i + 7], 0};

        char* end = nullptr;
        unsigned long idx = strtoul(idxHex, &end, 16);
        if (end == idxHex || *end != '\0') {
            Serial.print(F("[AssetCache] bad index in pixelsPacked at offset "));
            Serial.println(i);
            return false;
        }

        unsigned long col = strtoul(colHex, &end, 16);
        if (end == colHex || *end != '\0') {
            Serial.print(F("[AssetCache] bad colour in pixelsPacked at offset "));
            Serial.println(i);
            return false;
        }

        Pixel pixel;
        pixel.index = (uint8_t)idx;
        pixel.color = (uint32_t)col;
        out.push_back(pixel);
    }
    return true;
}

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
    if (asset.encoding == "SPARSE_PACKED_V1") {
        if (!doc.containsKey("pixelsPacked")) {
            Serial.println(F("[AssetCache] SPARSE_PACKED_V1 asset has no pixelsPacked field"));
            return false;
        }
        if (!parsePackedPixels(doc["pixelsPacked"].as<const char*>(), asset.pixels)) {
            return false;
        }
    } else if (asset.encoding == "SPARSE_I16_RGB888") {
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
    } else {
        // Previously this fell through and returned true, so an unreadable
        // asset was cached as "valid" and rendered as a black screen.
        Serial.print(F("[AssetCache] Unknown encoding: '"));
        Serial.print(asset.encoding);
        Serial.println(F("'"));
        return false;
    }

    // An asset that parsed to nothing renders identically to a failure, so
    // treat it as one rather than caching an empty image.
    if (asset.encoding == "DELTA_SPARSE_I16_RGB888") {
        if (asset.basePixels.empty() && asset.frames.empty()) {
            Serial.print(F("[AssetCache] Animation has no base pixels or frames: "));
            Serial.println(assetId);
            return false;
        }
    } else if (asset.pixels.empty()) {
        Serial.print(F("[AssetCache] Image parsed to zero pixels: "));
        Serial.println(assetId);
        return false;
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
