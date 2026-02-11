#include "MatrixDriver.h"

MatrixDriver::MatrixDriver() 
    : strip(MATRIX_WIDTH * MATRIX_HEIGHT, NEOPIXEL_PIN, NEOPIXEL_TYPE),
      currentBrightness(DEFAULT_BRIGHTNESS) {
}

MatrixDriver::~MatrixDriver() {
}

bool MatrixDriver::begin() {
    strip.begin();
    strip.setBrightness(currentBrightness);
    strip.clear();
    strip.show();
    Serial.println("[Matrix] Initialized");
    return true;
}

void MatrixDriver::setBrightness(uint8_t brightness) {
    currentBrightness = brightness;
    strip.setBrightness(brightness);
    Serial.print("[Matrix] Brightness set to: ");
    Serial.println(brightness);
}

void MatrixDriver::setPixel(uint8_t x, uint8_t y, uint32_t color) {
    if (x >= MATRIX_WIDTH || y >= MATRIX_HEIGHT) return;
    uint16_t index = xyToIndex(x, y);
    strip.setPixelColor(index, color);
}

void MatrixDriver::setPixel(uint8_t x, uint8_t y, uint8_t r, uint8_t g, uint8_t b) {
    setPixel(x, y, color(r, g, b));
}

void MatrixDriver::clear() {
    strip.clear();
}

void MatrixDriver::show() {
    strip.show();
}

void MatrixDriver::fill(uint32_t color) {
    for (uint16_t i = 0; i < numPixels(); i++) {
        strip.setPixelColor(i, color);
    }
}

void MatrixDriver::fill(uint8_t r, uint8_t g, uint8_t b) {
    fill(color(r, g, b));
}

uint32_t MatrixDriver::color(uint8_t r, uint8_t g, uint8_t b) {
    return strip.Color(r, g, b);
}

uint32_t MatrixDriver::color(uint32_t rgb888) {
    // Convert 0xRRGGBB to NeoPixel format
    uint8_t r = (rgb888 >> 16) & 0xFF;
    uint8_t g = (rgb888 >> 8) & 0xFF;
    uint8_t b = rgb888 & 0xFF;
    return color(r, g, b);
}

uint16_t MatrixDriver::xyToIndex(uint8_t x, uint8_t y) {
    // Serpentine mapping: even rows go left-to-right, odd rows go right-to-left
    uint8_t row = y;
    uint8_t col = x;
    
    if (row % 2 == 0) {
        // Even row: left to right
        return row * MATRIX_WIDTH + col;
    } else {
        // Odd row: right to left
        return row * MATRIX_WIDTH + (MATRIX_WIDTH - 1 - col);
    }
}
