#include "AssetCache.h"
#include <ArduinoJson.h>

// Parse a packed pixel run: fixed-width 8-char groups, "IIRRGGBB" per pixel.
// II = pixel index 0-255, RRGGBB = colour. No separators, so a whole image is
// one Firestore string field instead of one map per pixel. The old per-pixel
// encoding pushed the asset document to ~23KB, which the Firebase client
// cannot buffer without PSRAM - the fetch then returned an empty body with no
// error code and the screen rendered black.
//
// `allowEmpty` is true for animation deltas: a frame that changes nothing is
// legitimate, while an image with no pixels is a failure.
static bool parsePackedPixels(const char* packed, std::vector<Pixel>& out,
                              bool allowEmpty = false) {
    if (packed == nullptr) return false;

    size_t len = strlen(packed);
    if (len == 0) {
        if (allowEmpty) return true;
        Serial.println(F("[AssetCache] packed pixel string is empty"));
        return false;
    }
    if (len > 2048 || len % 8 != 0) {
        Serial.print(F("[AssetCache] packed length not a multiple of 8: "));
        Serial.println(len);
        return false;
    }

    out.reserve(out.size() + len / 8);
    for (size_t i = 0; i < len; i += 8) {
        char idxHex[3] = {packed[i], packed[i + 1], 0};
        char colHex[7] = {packed[i + 2], packed[i + 3], packed[i + 4],
                          packed[i + 5], packed[i + 6], packed[i + 7], 0};

        char* end = nullptr;
        unsigned long idx = strtoul(idxHex, &end, 16);
        if (end == idxHex || *end != '\0') {
            Serial.print(F("[AssetCache] bad index in packed data at offset "));
            Serial.println(i);
            return false;
        }
        if (idx > 255) {
            Serial.print(F("[AssetCache] pixel index out of range: "));
            Serial.println(idx);
            return false;
        }

        unsigned long col = strtoul(colHex, &end, 16);
        if (end == colHex || *end != '\0') {
            Serial.print(F("[AssetCache] bad colour in packed data at offset "));
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

// Reads DELTA_SPARSE_PACKED_V1. Frames land in the cache already cumulative:
// frames[0].delta is the whole first frame, frames[i].delta is the change from
// frame i-1.
static bool parsePackedAnimation(JsonObject doc, CachedAsset& asset) {
    if (doc["basePixelsPacked"].isNull() ||
        doc["frameDurationsMs"].isNull()) {
        Serial.println(F("[AssetCache] packed animation missing base or durations"));
        return false;
    }

    if (!doc["basePixelsPacked"].is<const char*>() || !doc["frameDurationsMs"].is<JsonArray>() || !doc["frameDeltasPacked"].is<JsonArray>()) return false;
    JsonArray durations = doc["frameDurationsMs"];
    JsonArray deltas = doc["frameDeltasPacked"];

    size_t frameCount = durations.size();
    if (frameCount < ANIM_MIN_FRAMES || frameCount > ANIM_MAX_FRAMES) {
        Serial.print(F("[AssetCache] frame count out of range: "));
        Serial.println(frameCount);
        return false;
    }
    // One transition per frame after the first. A mismatch means the document
    // was written by something that does not agree with this format.
    if (deltas.size() != frameCount - 1) {
        Serial.print(F("[AssetCache] delta count "));
        Serial.print(deltas.size());
        Serial.print(F(" does not match frame count "));
        Serial.println(frameCount);
        return false;
    }
    if (!doc["frameCount"].isNull() &&
        (size_t)doc["frameCount"].as<int>() != frameCount) {
        Serial.println(F("[AssetCache] frameCount disagrees with frameDurationsMs"));
        return false;
    }

    const char* base = doc["basePixelsPacked"].as<const char*>();
    size_t packedChars = base == nullptr ? 0 : strlen(base);
    for (JsonVariant d : deltas) {
        const char* s = d.as<const char*>();
        packedChars += (s == nullptr ? 0 : strlen(s));
    }
    if (packedChars > ANIM_MAX_PACKED_CHARS) {
        Serial.print(F("[AssetCache] packed animation too large: "));
        Serial.println(packedChars);
        return false;
    }

    for (size_t i = 0; i < frameCount; i++) {
        if (!durations[i].is<int>()) return false;
        int duration = durations[i].as<int>();
        if (duration < (int)ANIM_MIN_DURATION_MS ||
            duration > (int)ANIM_MAX_DURATION_MS) {
            Serial.print(F("[AssetCache] frame duration out of range: "));
            Serial.println(duration);
            return false;
        }

        AnimationFrame frame;
        frame.durationMs = (uint16_t)duration;
        const char* packed = (i == 0) ? base : deltas[i - 1].as<const char*>();
        // The base may legitimately be empty when frame 0 is blank and later
        // deltas light the panel up.
        if (!parsePackedPixels(packed, frame.delta, true)) return false;
        asset.frames.push_back(std::move(frame));
    }

    return true;
}

// Reads the older DELTA_SPARSE_I16_RGB888 form, where every frame is a delta
// against the *base* rather than against the frame before it. Converting here
// means playback has one code path; editing such an asset in the app rewrites
// it in the packed format.
static bool parseLegacyAnimation(JsonObject doc, CachedAsset& asset) {
    uint32_t base[256];
    memset(base, 0, sizeof(base));

    if (!doc["basePixels"].isNull()) {
        JsonArray baseArray = doc["basePixels"];
        for (JsonArray pixelArray : baseArray) {
            if (pixelArray.size() >= 2) {
                int index = pixelArray[0].as<int>();
                if (index < 0 || index > 255) continue;
                base[index] = pixelArray[1].as<uint32_t>();
            }
        }
    }

    if (doc["frames"].isNull()) {
        Serial.println(F("[AssetCache] legacy animation has no frames"));
        return false;
    }

    JsonArray framesArray = doc["frames"];
    if (framesArray.size() < ANIM_MIN_FRAMES ||
        framesArray.size() > ANIM_MAX_FRAMES) {
        Serial.print(F("[AssetCache] legacy frame count out of range: "));
        Serial.println(framesArray.size());
        return false;
    }

    uint32_t previous[256];
    memset(previous, 0, sizeof(previous));
    bool first = true;

    for (JsonObject frameObj : framesArray) {
        uint32_t current[256];
        memcpy(current, base, sizeof(base));

        if (!frameObj["pixels"].isNull()) {
            for (JsonArray pixelArray : frameObj["pixels"].as<JsonArray>()) {
                if (pixelArray.size() >= 2) {
                    int index = pixelArray[0].as<int>();
                    if (index < 0 || index > 255) continue;
                    current[index] = pixelArray[1].as<uint32_t>();
                }
            }
        }

        AnimationFrame frame;
        int delay = !frameObj["delayMs"].isNull() ? frameObj["delayMs"].as<int>() : 0;
        if (delay < (int)ANIM_MIN_DURATION_MS) delay = ANIM_MIN_DURATION_MS;
        if (delay > (int)ANIM_MAX_DURATION_MS) delay = ANIM_MAX_DURATION_MS;
        frame.durationMs = (uint16_t)delay;

        for (int i = 0; i < 256; i++) {
            // Frame 0 carries every lit pixel; later frames carry only what
            // actually changed since the previous absolute frame.
            if (first ? current[i] != 0 : current[i] != previous[i]) {
                Pixel pixel;
                pixel.index = (uint8_t)i;
                pixel.color = current[i];
                frame.delta.push_back(pixel);
            }
        }

        asset.frames.push_back(std::move(frame));
        memcpy(previous, current, sizeof(current));
        first = false;
    }

    return true;
}

AssetCache::AssetCache() {
}

AssetCache::~AssetCache() {
    clear();
}

bool AssetCache::addAsset(const CachedAsset& asset) {
    CachedAsset copy=asset;return addAsset(std::move(copy));
}
bool AssetCache::addAsset(CachedAsset&& asset) {
    auto value=std::make_shared<CachedAsset>(std::move(asset));
    for(auto& existing:assets) if(existing->id==value->id){existing=std::move(value);return true;}
    assets.push_back(std::move(value));return true;
}
bool AssetCache::removeAsset(const String& id) {
    for(auto it=assets.begin();it!=assets.end();++it)if((*it)->id==id){assets.erase(it);return true;}return false;
}
void AssetCache::clear(){assets.clear();}
size_t AssetCache::retainOnly(const std::vector<String>& ids){
    size_t removed=0;for(auto it=assets.begin();it!=assets.end();){bool keep=false;
      for(const auto& id:ids)if((*it)->id==id){keep=true;break;}
      if(keep)++it;else{it=assets.erase(it);++removed;}}return removed;
}
std::shared_ptr<CachedAsset> AssetCache::getSharedAsset(const String& id){
    for(const auto& a:assets)if(a->id==id)return a;return {};
}
CachedAsset* AssetCache::getAsset(const String& id){return getSharedAsset(id).get();}

bool AssetCache::parseAsset(const String& assetId, const String& jsonStr, CachedAsset& asset) {
    asset.id = assetId;
    asset.pixels.clear();
    asset.frames.clear();

    // ArduinoJson 7: the document grows on demand, so there is no capacity to
    // get wrong. The fixed 8192 this used to carry could not hold an animation
    // of ANIM_MAX_PACKED_CHARS - it failed with NoMemory and the screen showed
    // as a load error - while a fixed 16384 wasted most of itself on an
    // ordinary image. Pressure now surfaces as heap exhaustion instead.
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, jsonStr);

    if (error) {
        Serial.print(F("[AssetCache] JSON parse error: "));
        Serial.println(error.c_str());
        return false;
    }

    return parseAssetObject(assetId,doc.as<JsonObject>(),asset);
}
bool AssetCache::parseAssetObject(const String& assetId,JsonObject root,CachedAsset& asset){
    asset=CachedAsset();asset.id=assetId;

    // Parse type
    if (!root["type"].isNull()) {
        asset.type = root["type"].as<String>();
    }

    asset.type.toUpperCase();

    // Parse encoding
    if (!root["encoding"].isNull()) {
        asset.encoding = root["encoding"].as<String>();
    }

    // Parse based on encoding
    if (asset.encoding == "SPARSE_PACKED_V1") {
        if (root["pixelsPacked"].isNull()) {
            Serial.println(F("[AssetCache] SPARSE_PACKED_V1 asset has no pixelsPacked field"));
            return false;
        }
        if (!root["pixelsPacked"].is<const char*>() || strlen(root["pixelsPacked"].as<const char*>())>2048 || !parsePackedPixels(root["pixelsPacked"].as<const char*>(), asset.pixels,true)) {
            return false;
        }
    } else if (asset.encoding == "SPARSE_I16_RGB888") {
        if (!root["pixels"].isNull()) {
            JsonArray pixelsArray = root["pixels"];
            for (JsonArray pixelArray : pixelsArray) {
                if (pixelArray.size() >= 2) {
                    Pixel pixel;
                    pixel.index = pixelArray[0].as<uint8_t>();
                    pixel.color = pixelArray[1].as<uint32_t>();
                    asset.pixels.push_back(pixel);
                }
            }
        }
    } else if (asset.encoding == "DELTA_SPARSE_PACKED_V1") {
        if (!parsePackedAnimation(root, asset)) return false;
    } else if (asset.encoding == "DELTA_SPARSE_I16_RGB888") {
        if (!parseLegacyAnimation(root, asset)) return false;
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
    if (asset.isAnimation()) {
        bool anyVisible = false;
        for (const auto& frame : asset.frames) {
            for (const auto& pixel : frame.delta) {
                if (pixel.color != 0) { anyVisible = true; break; }
            }
            if (anyVisible) break;
        }
        if (!anyVisible) {
            Serial.print(F("[AssetCache] Animation has no visible pixel: "));
            Serial.println(assetId);
            return false;
        }
    }
    // Legacy ANIMATION records can contain a still image; publish what is displayed.
    if (!asset.isAnimation() && asset.type=="ANIMATION") asset.type="IMAGE";
    if ((asset.encoding.startsWith("DELTA_") && asset.type!="ANIMATION") ||
        (!asset.encoding.startsWith("DELTA_") && asset.type!="IMAGE")) return false;
    return true;
}
