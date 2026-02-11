#ifndef ASSET_CACHE_H
#define ASSET_CACHE_H

#include <Arduino.h>
#include <vector>

/**
 * Asset cache for storing parsed pixel data
 * Supports SPARSE_I16_RGB888 and DELTA_SPARSE_I16_RGB888 formats
 */
struct Pixel {
    uint8_t index;  // 0-255 (y*16 + x)
    uint32_t color; // 0xRRGGBB
};

struct AnimationFrame {
    uint16_t delayMs;
    std::vector<Pixel> pixels;
};

struct CachedAsset {
    String id;
    String type; // IMAGE, ANIMATION
    String encoding;
    
    // For SPARSE_I16_RGB888 (IMAGE)
    std::vector<Pixel> pixels;
    
    // For DELTA_SPARSE_I16_RGB888 (ANIMATION)
    std::vector<Pixel> basePixels;
    std::vector<AnimationFrame> frames;
    bool loop;
    
    bool isValid() const { return id.length() > 0; }
};

class AssetCache {
public:
    AssetCache();
    ~AssetCache();
    
    // Add/update asset
    bool addAsset(const CachedAsset& asset);
    bool removeAsset(const String& assetId);
    void clear();
    
    // Get asset
    CachedAsset* getAsset(const String& assetId);
    
    // Parse from Firestore JSON
    bool parseAsset(const String& assetId, const String& jsonStr, CachedAsset& asset);
    
    size_t size() const { return assets.size(); }
    
private:
    std::vector<CachedAsset> assets;
    
    bool parseSparsePixels(const String& jsonStr, std::vector<Pixel>& pixels);
    bool parseDeltaFrames(const String& jsonStr, std::vector<Pixel>& basePixels, std::vector<AnimationFrame>& frames);
};

#endif // ASSET_CACHE_H
