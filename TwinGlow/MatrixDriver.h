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
    
    // Serpentine mapping: convert (x,y) to pixel index
    uint16_t xyToIndex(uint8_t x, uint8_t y);
};

#endif // MATRIX_DRIVER_H
