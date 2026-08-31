#include "RenderAsset.h"

RenderAsset::RenderAsset(MatrixDriver* mat)
    : matrix(mat), frameShownAtMs(0), currentFrameIndex(0),
      currentAnimation(nullptr), needsRestart(true) {
    memset(frameBuffer, 0, sizeof(frameBuffer));
}

void RenderAsset::renderImage(CachedAsset* asset, uint32_t bgColor) {
    if (asset == nullptr || !asset->isValid()) {
        // A missing asset used to fill bgColor, which is indistinguishable from
        // a legitimately dark image. Dim red marks "asset failed to load" so the
        // fault is visible on the matrix without a serial cable.
        matrix->fill(matrix->color(ASSET_ERROR_COLOR));
        matrix->show();
        return;
    }

    if (asset->encoding == "SPARSE_PACKED_V1" || asset->encoding == "SPARSE_I16_RGB888") {
        renderPixels(asset->pixels, bgColor);
    } else {
        matrix->fill(matrix->color(ASSET_ERROR_COLOR));
    }

    matrix->show();
}

bool RenderAsset::renderAnimation(CachedAsset* asset, uint32_t bgColor) {
    if (asset == nullptr || !asset->isValid()) {
        matrix->fill(matrix->color(ASSET_ERROR_COLOR));
        matrix->show();
        return false;
    }

    // An asset typed ANIMATION that holds a still image still renders.
    if (!asset->isAnimation()) {
        renderImage(asset, bgColor);
        return false;
    }

    // Switching asset restarts at frame 0 rather than resuming at whatever
    // index the previous animation happened to be on.
    if (asset != currentAnimation || needsRestart) {
        currentAnimation = asset;
        needsRestart = false;
        currentFrameIndex = 0;
        memset(frameBuffer, 0, sizeof(frameBuffer));
        applyFrame(0);
        // Frame 0 is on screen immediately; its duration is how long it stays.
        frameShownAtMs = millis();
        paintFrameBuffer(bgColor);
        return false;
    }

    unsigned long now = millis();
    bool advanced = false;

    // A duration describes how long its own frame is visible, so the move
    // happens once that frame has had its time.
    if (now - frameShownAtMs >= currentAnimation->frames[currentFrameIndex].durationMs) {
        currentFrameIndex++;
        if (currentFrameIndex >= currentAnimation->frames.size()) {
            // Always loops. The last frame returns to frame 0, which means
            // rebuilding from a cleared buffer because deltas only move
            // forward.
            currentFrameIndex = 0;
            memset(frameBuffer, 0, sizeof(frameBuffer));
        }
        applyFrame(currentFrameIndex);
        frameShownAtMs = now;
        advanced = true;
    }

    paintFrameBuffer(bgColor);
    return advanced;
}

void RenderAsset::resetAnimation() {
    currentFrameIndex = 0;
    frameShownAtMs = millis();
    // Cleared because a config reload can reallocate the cache's vector and
    // leave this pointing at freed memory. It is only ever compared, never
    // dereferenced, but there is no reason to keep a stale value around.
    currentAnimation = nullptr;
    // Forces the next renderAnimation() to rebuild the buffer from frame 0,
    // even when the asset pointer has not changed.
    needsRestart = true;
}

void RenderAsset::applyFrame(size_t index) {
    if (currentAnimation == nullptr || index >= currentAnimation->frames.size()) return;
    for (const auto& pixel : currentAnimation->frames[index].delta) {
        // A delta entry with colour 0 clears that pixel.
        frameBuffer[pixel.index] = pixel.color;
    }
}

void RenderAsset::paintFrameBuffer(uint32_t bgColor) {
    matrix->fill(bgColor);
    for (int i = 0; i < 256; i++) {
        if (frameBuffer[i] == 0) continue; // off: leave the background showing
        uint8_t x = i % MATRIX_WIDTH;
        uint8_t y = i / MATRIX_WIDTH;
        matrix->setPixelOriented(x, y, matrix->color(frameBuffer[i]));
    }
    matrix->show();
}

void RenderAsset::renderPixels(const std::vector<Pixel>& pixels, uint32_t bgColor) {
    // Clear to background
    matrix->fill(bgColor);

    // Render pixels
    for (const auto& pixel : pixels) {
        uint8_t x = pixel.index % MATRIX_WIDTH;
        uint8_t y = pixel.index / MATRIX_WIDTH;
        matrix->setPixelOriented(x, y, matrix->color(pixel.color));
    }
}
