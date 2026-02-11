#include "RenderAsset.h"

RenderAsset::RenderAsset(MatrixDriver* mat) 
    : matrix(mat), lastFrameMs(0), currentFrameIndex(0), currentAnimation(nullptr) {
}

void RenderAsset::renderImage(CachedAsset* asset, uint32_t bgColor) {
    if (asset == nullptr || !asset->isValid()) {
        matrix->fill(bgColor);
        matrix->show();
        return;
    }
    
    if (asset->encoding == "SPARSE_I16_RGB888") {
        renderPixels(asset->pixels, bgColor);
    } else {
        matrix->fill(bgColor);
    }
    
    matrix->show();
}

bool RenderAsset::renderAnimation(CachedAsset* asset, uint32_t bgColor) {
    if (asset == nullptr || !asset->isValid()) {
        matrix->fill(bgColor);
        matrix->show();
        return false;
    }
    
    if (asset->encoding != "DELTA_SPARSE_I16_RGB888") {
        renderImage(asset, bgColor);
        return false;
    }
    
    // Check if animation changed
    if (asset != currentAnimation) {
        currentAnimation = asset;
        currentFrameIndex = 0;
        lastFrameMs = millis();
    }
    
    // Check if it's time for next frame
    if (asset->frames.empty()) {
        renderPixels(asset->basePixels, bgColor);
        matrix->show();
        return false;
    }
    
    unsigned long now = millis();
    AnimationFrame& frame = asset->frames[currentFrameIndex];
    
    if (now - lastFrameMs >= frame.delayMs) {
        // Render current frame
        applyDeltaFrame(asset->basePixels, frame.pixels, bgColor);
        matrix->show();
        
        // Advance to next frame
        currentFrameIndex++;
        if (currentFrameIndex >= asset->frames.size()) {
            if (asset->loop) {
                currentFrameIndex = 0;
            } else {
                currentFrameIndex = asset->frames.size() - 1; // Stay on last frame
            }
        }
        
        lastFrameMs = now;
        return true;
    } else {
        // Render current frame without advancing
        applyDeltaFrame(asset->basePixels, frame.pixels, bgColor);
        matrix->show();
        return false;
    }
}

void RenderAsset::resetAnimation() {
    currentFrameIndex = 0;
    lastFrameMs = millis();
}

void RenderAsset::renderPixels(const std::vector<Pixel>& pixels, uint32_t bgColor) {
    // Clear to background
    matrix->fill(bgColor);
    
    // Render pixels
    for (const auto& pixel : pixels) {
        uint8_t x = pixel.index % 16;
        uint8_t y = pixel.index / 16;
        matrix->setPixel(x, y, matrix->color(pixel.color));
    }
}

void RenderAsset::applyDeltaFrame(const std::vector<Pixel>& basePixels, const std::vector<Pixel>& deltaPixels, uint32_t bgColor) {
    // Start with base pixels
    renderPixels(basePixels, bgColor);
    
    // Apply delta pixels (can include black to turn off)
    for (const auto& pixel : deltaPixels) {
        uint8_t x = pixel.index % 16;
        uint8_t y = pixel.index / 16;
        if (pixel.color == 0) {
            matrix->setPixel(x, y, bgColor);
        } else {
            matrix->setPixel(x, y, matrix->color(pixel.color));
        }
    }
}
