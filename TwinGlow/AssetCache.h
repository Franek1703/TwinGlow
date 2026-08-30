#ifndef ASSET_CACHE_H
#define ASSET_CACHE_H

#include <Arduino.h>
#include <vector>

/**
 * Asset cache for storing parsed pixel data
 *
 * Images arrive as SPARSE_PACKED_V1 (or the older SPARSE_I16_RGB888).
 * Animations arrive as DELTA_SPARSE_PACKED_V1, which packs the first frame in
 * full and every later frame as the change from the one before it. The older
 * DELTA_SPARSE_I16_RGB888 form is still read and converted on the way in, so
 * playback only ever deals with cumulative transitions.
 */
struct Pixel {
    uint8_t index;  // 0-255 (y*16 + x)
    uint32_t color; // 0xRRGGBB, 0 = off
};

// Limits mirrored from the app's AnimationCodec. The device re-checks them
// rather than trusting the document: a malformed asset must fail to parse, not
// render as a wrong or endless animation.
static const size_t ANIM_MIN_FRAMES = 2;
static const size_t ANIM_MAX_FRAMES = 16;
static const uint16_t ANIM_MIN_DURATION_MS = 50;
static const uint16_t ANIM_MAX_DURATION_MS = 5000;
// Base plus every delta. Kept in step with AssetCache's JSON document size:
// raising this without raising that buffer makes large assets fail to parse.
static const size_t ANIM_MAX_PACKED_CHARS = 8192;

/**
 * One authored frame.
 *
 * `delta` is the transition *into* this frame from the previous one; frame 0's
 * delta is the complete first frame. A pixel with colour 0 is turned off.
 * Storing transitions rather than whole frames is what keeps a 16-frame
 * animation inside the RAM budget of a plain ESP32.
 */
struct AnimationFrame {
    uint16_t durationMs;   // how long this frame stays visible
    std::vector<Pixel> delta;
};

struct CachedAsset {
    String id;
    String type; // IMAGE, ANIMATION
    String encoding;

    // IMAGE
    std::vector<Pixel> pixels;

    // ANIMATION - always looping; a legacy loop:false flag does not change it
    std::vector<AnimationFrame> frames;

    bool isValid() const { return id.length() > 0; }
    bool isAnimation() const { return !frames.empty(); }
};

class AssetCache {
public:
    AssetCache();
    ~AssetCache();

    // Add/update asset
    bool addAsset(const CachedAsset& asset);
    bool removeAsset(const String& assetId);
    void clear();

    // Drop every asset whose id is not in `keepIds`, so assets that screens no
    // longer reference stop occupying RAM after a config change.
    size_t retainOnly(const std::vector<String>& keepIds);

    // Get asset
    CachedAsset* getAsset(const String& assetId);

    // Parse from Firestore JSON
    bool parseAsset(const String& assetId, const String& jsonStr, CachedAsset& asset);

    size_t size() const { return assets.size(); }

private:
    std::vector<CachedAsset> assets;
};

#endif // ASSET_CACHE_H
