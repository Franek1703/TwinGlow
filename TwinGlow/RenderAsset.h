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
    
    // Render ANIMATION asset (returns true if frame advanced)
    bool renderAnimation(CachedAsset* asset, uint32_t bgColor);
    
    // Reset animation to start
    void resetAnimation();
    
private:
    MatrixDriver* matrix;
    
    unsigned long lastFrameMs;
    int currentFrameIndex;
    CachedAsset* currentAnimation;
    
    void renderPixels(const std::vector<Pixel>& pixels, uint32_t bgColor);
    void applyDeltaFrame(const std::vector<Pixel>& basePixels, const std::vector<Pixel>& deltaPixels, uint32_t bgColor);
};

#endif // RENDER_ASSET_H
