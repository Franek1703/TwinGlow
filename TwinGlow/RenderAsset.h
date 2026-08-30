#ifndef RENDER_ASSET_H
#define RENDER_ASSET_H

#include "MatrixDriver.h"
#include "AssetCache.h"

/**
 * Asset renderer for IMAGE and ANIMATION screens
 * Renders from cached asset data
 */
class RenderAsset {
public:
    RenderAsset(MatrixDriver* matrix);

    // Render IMAGE asset
    void renderImage(CachedAsset* asset, uint32_t bgColor);

    // Render ANIMATION asset (returns true if the frame advanced)
    bool renderAnimation(CachedAsset* asset, uint32_t bgColor);

    // Restart playback at frame 0. Called when an animation screen is entered,
    // when the asset changes, and on wake, so a hidden animation never resumes
    // part-way through with a stale timer.
    void resetAnimation();

private:
    MatrixDriver* matrix;

    // Cumulative frame state: the colour currently held by each of the 256
    // pixels, 0 meaning off. Deltas are applied onto this rather than being
    // recomputed from the base every frame.
    uint32_t frameBuffer[256];

    unsigned long frameShownAtMs;
    size_t currentFrameIndex;
    CachedAsset* currentAnimation;
    bool needsRestart;

    void renderPixels(const std::vector<Pixel>& pixels, uint32_t bgColor);
    void applyFrame(size_t index);
    void paintFrameBuffer(uint32_t bgColor);
};

#endif // RENDER_ASSET_H
