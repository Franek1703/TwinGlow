#include "MatrixDriver.h"
#include <math.h>

MatrixDriver::MatrixDriver() 
    : strip(MATRIX_WIDTH * MATRIX_HEIGHT, NEOPIXEL_PIN, NEOPIXEL_TYPE),
      currentBrightness(DEFAULT_BRIGHTNESS) {
}

MatrixDriver::~MatrixDriver() {
}

bool MatrixDriver::begin() {
    Serial.print(F("[Matrix] Initializing NeoPixel strip: pin="));
    Serial.print(NEOPIXEL_PIN);
    Serial.print(F(", pixels="));
    Serial.print(MATRIX_WIDTH * MATRIX_HEIGHT);
    Serial.print(F(", type="));
    Serial.println(NEOPIXEL_TYPE);
    
    // Build the sRGB -> linear PWM table before the first show(). 256 powf()
    // calls at boot is nothing, and keeping it a runtime table (rather than
    // Adafruit's built-in gamma8(), which hardcodes 2.6) lets GAMMA_EXPONENT be
    // tuned against the real panel and diffuser.
    for (uint16_t i = 0; i < 256; i++) {
        gammaTable[i] = (uint8_t)(powf(i / 255.0f, GAMMA_EXPONENT) * 255.0f + 0.5f);
    }
    Serial.print(F("[Matrix] Gamma correction: "));
#if GAMMA_CORRECTION
    Serial.println(GAMMA_EXPONENT);
#else
    Serial.println(F("disabled (raw PWM)"));
#endif

    // Initialize the strip (begin() is void, doesn't return bool)
    // This configures the pin and prepares the strip
    strip.begin();
    
    // Small delay to let hardware initialize
    delay(10);
    
    strip.setBrightness(currentBrightness);
    strip.clear();
    
    // canShow() checks if we can safely call show() without blocking
    // On first init, this should be true. If false, there might be a hardware issue.
    if (!strip.canShow()) {
        Serial.print(F("[Matrix] WARNING: canShow() returned false, waiting..."));
        unsigned long startWait = millis();
        while (!strip.canShow() && (millis() - startWait < 100)) {
            delayMicroseconds(10);
        }
        if (!strip.canShow()) {
            Serial.println(F(" still false after 100ms"));
            Serial.println(F("[Matrix] ERROR: Hardware issue - check pin, wiring, and power"));
            Serial.print(F("[Matrix] Try changing NEOPIXEL_PIN from "));
            Serial.print(NEOPIXEL_PIN);
            Serial.println(F(" to 5 in Config.h"));
            return false;
        }
        Serial.println(F(" ready now"));
    }
    
    strip.show();
    
    Serial.println(F("[Matrix] Initialized successfully"));
    return true;
}

void MatrixDriver::setBrightness(uint8_t brightness) {
    // if brightness is 0, set it to 1 to remember the color
    if(brightness == 0){
        brightness = 1;
    }
    currentBrightness = brightness;
    strip.setBrightness(brightness);
    strip.show();
    Serial.print(F("[Matrix] Brightness set to: "));
    Serial.println(brightness);
}

uint32_t MatrixDriver::applyGamma(uint32_t argb) const {
    // Screen configs arrive as Flutter's Color.value (0xAARRGGBB), so mask the
    // alpha off rather than relying on setPixelColor treating the top byte as an
    // unused white channel.
    uint32_t rgb = argb & 0x00FFFFFF;
#if GAMMA_CORRECTION
    uint8_t r = gammaTable[(rgb >> 16) & 0xFF];
    uint8_t g = gammaTable[(rgb >> 8) & 0xFF];
    uint8_t b = gammaTable[rgb & 0xFF];
    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
#else
    return rgb;
#endif
}

void MatrixDriver::setPixel(uint8_t x, uint8_t y, uint32_t color) {
    if (x >= MATRIX_WIDTH || y >= MATRIX_HEIGHT) return;
    uint16_t index = xyToIndex(x, y);
    strip.setPixelColor(index, applyGamma(color));
}

void MatrixDriver::setPixel(uint8_t x, uint8_t y, uint8_t r, uint8_t g, uint8_t b) {
    setPixel(x, y, color(r, g, b));
}

void MatrixDriver::setPixelOriented(uint8_t x, uint8_t y, uint32_t color) {
    // Bounds-checked in screen space, before the transform, so an out-of-range
    // coordinate cannot wrap into a valid panel pixel on the way through.
    if (x >= MATRIX_WIDTH || y >= MATRIX_HEIGHT) return;

#if PANEL_ORIENTATION == PANEL_ORIENT_NONE
    setPixel(x, y, color);
#elif PANEL_ORIENTATION == PANEL_ORIENT_ROT90
    setPixel((uint8_t)(MATRIX_WIDTH - 1 - y), x, color);
#elif PANEL_ORIENTATION == PANEL_ORIENT_ROT180
    setPixel((uint8_t)(MATRIX_WIDTH - 1 - x), (uint8_t)(MATRIX_HEIGHT - 1 - y), color);
#elif PANEL_ORIENTATION == PANEL_ORIENT_ROT270
    setPixel(y, (uint8_t)(MATRIX_HEIGHT - 1 - x), color);
#elif PANEL_ORIENTATION == PANEL_ORIENT_TRANSPOSE
    setPixel(y, x, color);
#else
#error "PANEL_ORIENTATION must be one of PANEL_ORIENT_NONE/ROT90/ROT180/ROT270/TRANSPOSE"
#endif
}

void MatrixDriver::setPixelOriented(uint8_t x, uint8_t y, uint8_t r, uint8_t g, uint8_t b) {
    setPixelOriented(x, y, color(r, g, b));
}

void MatrixDriver::clear() {
    strip.clear();
    strip.show();
}

void MatrixDriver::show() {
    strip.show();
}

void MatrixDriver::fill(uint32_t color) {
    // Corrected once here rather than per pixel - every LED gets the same value.
    uint32_t corrected = applyGamma(color);
    for (uint16_t i = 0; i < numPixels(); i++) {
        strip.setPixelColor(i, corrected);
    }
}

void MatrixDriver::fill(uint8_t r, uint8_t g, uint8_t b) {
    fill(color(r, g, b));
}

void MatrixDriver::fillStatus(uint32_t color) {
    // Cap linear PWM after gamma correction, so status screens stay dim even
    // with gamma disabled or the owner's brightness set to maximum. Normal
    // screen content still uses fill()/setPixel() at the selected brightness.
    constexpr uint8_t maxStatusPwm = 8;
    uint32_t corrected = applyGamma(color);
    uint8_t r = (corrected >> 16) & 0xFF;
    uint8_t g = (corrected >> 8) & 0xFF;
    uint8_t b = corrected & 0xFF;
    uint8_t peak = max(r, max(g, b));
    if (peak > maxStatusPwm) {
        r = (uint16_t)r * maxStatusPwm / peak;
        g = (uint16_t)g * maxStatusPwm / peak;
        b = (uint16_t)b * maxStatusPwm / peak;
    }
    uint32_t dimmed = ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
    for (uint16_t i = 0; i < numPixels(); i++) {
        strip.setPixelColor(i, dimmed);
    }
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

void MatrixDriver::testFill(uint8_t r, uint8_t g, uint8_t b) {
    Serial.print(F("[Matrix] Test fill: R="));
    Serial.print(r);
    Serial.print(F(" G="));
    Serial.print(g);
    Serial.print(F(" B="));
    Serial.println(b);
    fill(r, g, b);
    show();
}
