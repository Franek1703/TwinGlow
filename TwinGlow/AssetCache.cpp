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
// Firestore wraps strings/integers/arrays in Value objects. Reading those
// wrappers directly avoids a second JSON document and serialized payload.
static JsonVariant packedValue(JsonVariant value, bool firestore, const char* key) {
    if (firestore) return value[key].as<JsonVariant>();
    return value;
}
static bool packedInteger(JsonVariant value, bool firestore, int& result) {
    if (!firestore) {
        if (!value.is<int>()) return false;
        result = value.as<int>(); return true;
    }
    const char* text = value["integerValue"].as<const char*>();
    if (!text || !*text) return false;
    char* end = nullptr;
    long number = strtol(text, &end, 10);
    if (*end || number < 0 || number > 2147483647L) return false;
    result = (int)number; return true;
}
static bool parsePackedAnimation(JsonObject doc, CachedAsset& asset, bool firestore = false) {
    JsonVariant baseValue = packedValue(doc["basePixelsPacked"], firestore, "stringValue");
    JsonVariant durationsValue = firestore
        ? doc["frameDurationsMs"]["arrayValue"]["values"].as<JsonVariant>() : doc["frameDurationsMs"].as<JsonVariant>();
    JsonVariant deltasValue = firestore
        ? doc["frameDeltasPacked"]["arrayValue"]["values"].as<JsonVariant>() : doc["frameDeltasPacked"].as<JsonVariant>();
    if (!baseValue.is<const char*>() || !durationsValue.is<JsonArray>() || !deltasValue.is<JsonArray>()) return false;
    JsonArray durations = durationsValue.as<JsonArray>();
    JsonArray deltas = deltasValue.as<JsonArray>();
    size_t frameCount = durations.size();
    if (frameCount < ANIM_MIN_FRAMES || frameCount > ANIM_MAX_FRAMES || deltas.size() != frameCount - 1) return false;
    if (!doc["frameCount"].isNull()) {
        int count = 0;
        if (!packedInteger(doc["frameCount"], firestore, count) || (size_t)count != frameCount) return false;
    }
    const char* base = baseValue.as<const char*>();
    size_t packedChars = strlen(base);
    for (JsonVariant d : deltas) {
        JsonVariant value = packedValue(d, firestore, "stringValue");
        if (!value.is<const char*>()) return false;
        packedChars += strlen(value.as<const char*>());
    }
    if (packedChars > ANIM_MAX_PACKED_CHARS) return false;
    for (size_t i = 0; i < frameCount; i++) {
        int duration = 0;
        if (!packedInteger(durations[i], firestore, duration) ||
            duration < ANIM_MIN_DURATION_MS || duration > ANIM_MAX_DURATION_MS) return false;
        AnimationFrame frame;
        frame.durationMs = (uint16_t)duration;
        const char* packed = i == 0 ? base : packedValue(deltas[i - 1], firestore, "stringValue").as<const char*>();
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

static bool validateParsedAsset(CachedAsset& asset) {
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
            Serial.println(asset.id);
            return false;
        }
    }
    // Legacy ANIMATION records can contain a still image; publish what is displayed.
    if (!asset.isAnimation() && asset.type=="ANIMATION") asset.type="IMAGE";
    if ((asset.encoding.startsWith("DELTA_") && asset.type!="ANIMATION") ||
        (!asset.encoding.startsWith("DELTA_") && asset.type!="IMAGE")) return false;
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

    return validateParsedAsset(asset);
}

bool AssetCache::parseFirestorePackedAsset(const String& assetId, JsonObject fields, CachedAsset& asset) {
    asset = CachedAsset(); asset.id = assetId;
    if (!fields["type"]["stringValue"].is<const char*>() ||
        !fields["encoding"]["stringValue"].is<const char*>()) return false;
    asset.type = fields["type"]["stringValue"].as<const char*>();
    asset.type.toUpperCase();
    asset.encoding = fields["encoding"]["stringValue"].as<const char*>();
    if (asset.encoding == "SPARSE_PACKED_V1") {
        if (!parsePackedPixels(fields["pixelsPacked"]["stringValue"].as<const char*>(), asset.pixels, true)) return false;
    } else if (asset.encoding == "DELTA_SPARSE_PACKED_V1") {
        if (!parsePackedAnimation(fields, asset, true)) return false;
    } else return false;
    return validateParsedAsset(asset);
}
