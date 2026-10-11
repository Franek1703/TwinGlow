#pragma once
#include "Arduino.h"
#include <vector>
// Model the real library's GRB bytes and lossy brightness scaling. Capture
// transmitted bytes separately so temporary overlays can be checked exactly.
class Adafruit_NeoPixel {
    std::vector<uint8_t> bytes;
    uint8_t brightness = 0;
public:
    inline static std::vector<uint8_t> presented;
    inline static Adafruit_NeoPixel* active = nullptr;
    Adafruit_NeoPixel(unsigned n, int, int): bytes(n * 3) { active = this; }
    void begin() {}
    bool canShow() { return true; }
    uint8_t* getPixels() { return bytes.data(); }
    void clear() { std::fill(bytes.begin(), bytes.end(), 0); }
    void show() { presented = bytes; }
    void setBrightness(uint8_t b) {
        uint8_t next = b + 1, old = brightness - 1;
        if (next == brightness) return;
        uint16_t scale = old == 0 ? 0 : b == 255 ? 65535 / old : ((uint16_t(next) << 8) - 1) / old;
        for (auto& byte : bytes) byte = (byte * scale) >> 8;
        brightness = next;
    }
    void setPixelColor(unsigned n, uint32_t rgb) {
        uint8_t r = rgb >> 16, g = rgb >> 8, b = rgb;
        if (brightness) {
            r = (r * brightness) >> 8;
            g = (g * brightness) >> 8;
            b = (b * brightness) >> 8;
        }
        bytes.at(n * 3) = g; bytes.at(n * 3 + 1) = r; bytes.at(n * 3 + 2) = b;
    }
    static uint32_t Color(uint8_t r, uint8_t g, uint8_t b) { return (uint32_t(r) << 16) | (uint32_t(g) << 8) | b; }
};
