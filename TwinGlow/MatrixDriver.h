#ifndef MATRIX_DRIVER_H
#define MATRIX_DRIVER_H

#include <Adafruit_NeoPixel.h>
#include "Config.h"

/**
 * NeoPixel matrix driver with serpentine mapping
 * Handles 16x16 matrix with brightness control
 */
class MatrixDriver {
public:
    MatrixDriver();
    ~MatrixDriver();
    
    bool begin();
    void setBrightness(uint8_t brightness);
    uint8_t getBrightness() const { return currentBrightness; }
    
    // Pixel operations
    void setPixel(uint8_t x, uint8_t y, uint32_t color);
    void setPixel(uint8_t x, uint8_t y, uint8_t r, uint8_t g, uint8_t b);
    void clear();
    void show();
    
    // Fill operations
    void fill(uint32_t color);
    void fill(uint8_t r, uint8_t g, uint8_t b);
    
    // Utility
    uint32_t color(uint8_t r, uint8_t g, uint8_t b);
    uint32_t color(uint32_t rgb888); // Convert 0xRRGGBB to NeoPixel format
    
    // Test animations
    void testRainbow(unsigned long durationMs = 3000);
    void testFill(uint8_t r, uint8_t g, uint8_t b);
    
    uint16_t numPixels() const { return MATRIX_WIDTH * MATRIX_HEIGHT; }
    
private:
    Adafruit_NeoPixel strip;
    uint8_t currentBrightness;

    // sRGB -> linear PWM lookup, built once in begin(). The app hands us
    // gamma-encoded sRGB (what a phone screen shows); NeoPixel drives the byte
    // straight out as a duty cycle, so without this every secondary channel
    // emits several times too much light and saturated colours wash out - red
    // (244,67,54) reads as pink/purple on the panel.
    uint8_t gammaTable[256];

    // Drops the alpha byte the app packs into Color.value (0xAARRGGBB) and maps
    // R/G/B through gammaTable. No-op when GAMMA_CORRECTION is 0.
    uint32_t applyGamma(uint32_t argb) const;
    
    // Serpentine mapping: convert (x,y) to pixel index
    uint16_t xyToIndex(uint8_t x, uint8_t y);
};

#endif // MATRIX_DRIVER_H
