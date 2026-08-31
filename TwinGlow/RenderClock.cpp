#include "RenderClock.h"
#include "Config.h"
#include "PixelFont.h"

// Digit patterns live in PixelFont so RenderSensor can draw from the same data.

RenderClock::RenderClock(MatrixDriver* mat) : matrix(mat) {
}

void RenderClock::render(const String& format, const String& layout,
                         uint32_t fgColor, uint32_t accentColor, uint32_t bgColor,
                         bool showSeconds, bool blinkColon) {
    // Clear screen
    matrix->fill(bgColor);
    
    // Get current time
    time_t now = time(nullptr);
    if (now < 1000000000) {
        // Invalid time - show error pattern
        matrix->fill(matrix->color(255, 0, 0)); // Red
        matrix->show();
        return;
    }
    
    // localtime_r, not localtime: the result is broken out into a local buffer
    // rather than libc's shared static one, and the fields are read once here
    // and passed down. The layout helpers used to re-read the clock themselves,
    // which silently discarded whatever render() had computed.
    struct tm tmBuf;
    if (localtime_r(&now, &tmBuf) == nullptr) {
        matrix->fill(matrix->color(255, 0, 0)); // Red
        matrix->show();
        return;
    }

    int hour = tmBuf.tm_hour;
    int minute = tmBuf.tm_min;
    int second = tmBuf.tm_sec;

    // Log time being rendered (only every 5 seconds to avoid spam)
    static unsigned long lastTimeLogMs = 0;
    static int lastLoggedSecond = -1;
    if (second != lastLoggedSecond && (millis() - lastTimeLogMs >= 5000)) {
        lastTimeLogMs = millis();
        lastLoggedSecond = second;
        Serial.print(F("[RenderClock] Rendering time: "));
        Serial.print(hour);
        Serial.print(F(":"));
        if (minute < 10) Serial.print(F("0"));
        Serial.print(minute);
        Serial.print(F(":"));
        if (second < 10) Serial.print(F("0"));
        Serial.print(second);
        Serial.print(F(" (epoch="));
        Serial.print(now);
        Serial.println(F(")"));
    }
    
    // Convert to 12H if needed
    if (format == "12H") {
        if (hour == 0) hour = 12;
        else if (hour > 12) hour -= 12;
    }
    
    // A 12-hour clock reads "8:30", not "08:30"; a 24-hour one keeps the zero.
    // Decided here, where the format is known, and passed down - the digit
    // renderer used to try to infer it from the pixel coordinates it was handed.
    bool suppressLeadingZero = (format == "12H");

    // Render based on layout
    if (layout == "BIG_HHMM") {
        renderBigHHMM(hour, minute, fgColor, accentColor, bgColor, blinkColon, suppressLeadingZero);
    } else if (layout == "HHMM_PLUS_SECONDS_BAR") {
        renderHHMMPlusSecondsBar(hour, minute, second, fgColor, accentColor, bgColor, blinkColon, suppressLeadingZero);
    } else if (layout == "MINIMAL") {
        renderMinimal(hour, minute, fgColor, accentColor, bgColor, blinkColon, suppressLeadingZero);
    } else {
        // Default to BIG_HHMM
        renderBigHHMM(hour, minute, fgColor, accentColor, bgColor, blinkColon, suppressLeadingZero);
    }
    
    matrix->show();
}

void RenderClock::renderBigHHMM(int hour, int minute, uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon, bool suppressLeadingZero) {
    // Draw HH:MM - digits are 3 pixels wide, no spacing
    // First digit starts at x=0, second at x=3, colon at x=6, minutes at x=8 and x=11
    drawDigit(0, 4, hour / 10, fgColor, suppressLeadingZero);
    drawDigit(4, 4, hour % 10, fgColor);
    // y=6 centres the two 2x2 segments (rows 6-7 and 9-10) on the digits'
    // 9-row band (rows 4-12). The old y=5 was tuned against the mirrored frame
    // drawColon() used to rotate into, where it came out one row lower.
    drawColon(7, 6, accentColor, blinkColon);
    drawDigit(9, 4, minute / 10, fgColor);
    drawDigit(13, 4, minute % 10, fgColor);
}

void RenderClock::renderHHMMPlusSecondsBar(int hour, int minute, int second, uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon, bool suppressLeadingZero) {
    // Draw HH:MM - digits are 3 pixels wide, no spacing
    // First digit starts at x=0, second at x=3, colon at x=6, minutes at x=8 and x=11
    drawDigit(0, 4, hour / 10, fgColor, suppressLeadingZero);
    drawDigit(4, 4, hour % 10, fgColor);
    // y=6 centres the two 2x2 segments (rows 6-7 and 9-10) on the digits'
    // 9-row band (rows 4-12). The old y=5 was tuned against the mirrored frame
    // drawColon() used to rotate into, where it came out one row lower.
    drawColon(7, 6, accentColor, blinkColon);
    drawDigit(9, 4, minute / 10, fgColor);
    drawDigit(13, 4, minute % 10, fgColor);
    
    // Draw seconds bar at bottom
    drawSecondsBar(second, accentColor);
}

void RenderClock::renderMinimal(int hour, int minute, uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon, bool suppressLeadingZero) {
    // Smaller digits
    drawDigit(2, 6, hour / 10, fgColor, suppressLeadingZero);
    drawDigit(6, 6, hour % 10, fgColor);
    drawColon(10, 8, accentColor, blinkColon); // centred on the digits' rows 6-14
    drawDigit(12, 6, minute / 10, fgColor);
    drawDigit(14, 6, minute % 10, fgColor);
}

void RenderClock::drawPatternPixel(uint8_t patternX, uint8_t patternY, uint8_t baseX, uint8_t baseY, uint32_t color) {
    // Screen coordinates only. The panel's mounted orientation is applied once,
    // by setPixelOriented(), for every renderer.
    uint8_t absX = baseX + patternX;
    uint8_t absY = baseY + patternY;
    
    matrix->setPixelOriented(absX, absY, color);
}

void RenderClock::drawPatternDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color, bool suppressLeadingZero) {
    if (digit > 9) return;
    // The caller decides whether this slot is a suppressible leading zero. The
    // old test - digit == 0 && x == 0 && y == 0 - could never fire, because
    // every layout draws the hours at y = 4 or y = 6.
    if (suppressLeadingZero && digit == 0) return;

    const uint8_t* pattern = PixelFont::digitBig(digit);
    if (pattern == nullptr) return;
    
    // Draw 3x9 pattern (3 columns, 9 rows)
    for (uint8_t row = 0; row < 9; row++) {
        for (uint8_t col = 0; col < 3; col++) {
            if (pattern[(row * 3) + col] == 1) {
                drawPatternPixel(col, row, x, y, color);
            }
        }
    }
}

void RenderClock::drawDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color, bool suppressLeadingZero) {
    // Use pattern-based rendering with rotation
    drawPatternDigit(x, y, digit, color, suppressLeadingZero);
}

void RenderClock::drawColon(uint8_t x, uint8_t y, uint32_t color, bool blink) {
    if (blink && (millis() / 500) % 2 == 0) {
        return; // Blink off
    }
    
    // Draw colon as two 2x2 pixel segments (no spacing)
    // Top segment: 2x2 pixels at (x, y) to (x+1, y+1)
    // Bottom segment: 2x2 pixels at (x, y+3) to (x+1, y+4)
    // These used to carry their own 90-degree rotation, which is a mirror of the
    // one the digits used - the colon landed a pixel off and flipped.
    for (uint8_t dx = 0; dx < 2; dx++) {
        for (uint8_t dy = 0; dy < 2; dy++) {
            matrix->setPixelOriented(x + dx, y + dy, color);
            matrix->setPixelOriented(x + dx, y + 3 + dy, color);
        }
    }
}

void RenderClock::drawSecondsBar(uint8_t seconds, uint32_t color) {
    // Progress bar along the bottom row of the screen. It used to hardcode the
    // panel column its own rotation put that row in, which was the opposite edge
    // from the one the digits' mapping implies.
    int pixels = (seconds * MATRIX_WIDTH) / 60;
    for (int i = 0; i < pixels && i < MATRIX_WIDTH; i++) {
        matrix->setPixelOriented((uint8_t)i, MATRIX_HEIGHT - 1, color);
    }
}

void RenderClock::draw7Segment(uint8_t x, uint8_t y, uint8_t digit, uint32_t color) {
    // Simplified 7-segment rendering for 16x16 matrix
    // Each digit is 3x5 pixels
    // Basic patterns for digits 0-9
    
    // Clear digit area first
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 5; j++) {
            matrix->setPixelOriented(x + i, y + j, 0); // Black
        }
    }
    
    // 7-segment pattern: segments are numbered:
    //   0
    // 1   2
    //   3
    // 4   5
    //   6
    
    bool segments[7] = {false};
    
    switch (digit) {
        case 0: segments[0]=1; segments[1]=1; segments[2]=1; segments[4]=1; segments[5]=1; segments[6]=1; break;
        case 1: segments[2]=1; segments[5]=1; break;
        case 2: segments[0]=1; segments[2]=1; segments[3]=1; segments[4]=1; segments[6]=1; break;
        case 3: segments[0]=1; segments[2]=1; segments[3]=1; segments[5]=1; segments[6]=1; break;
        case 4: segments[1]=1; segments[2]=1; segments[3]=1; segments[5]=1; break;
        case 5: segments[0]=1; segments[1]=1; segments[3]=1; segments[5]=1; segments[6]=1; break;
        case 6: segments[0]=1; segments[1]=1; segments[3]=1; segments[4]=1; segments[5]=1; segments[6]=1; break;
        case 7: segments[0]=1; segments[2]=1; segments[5]=1; break;
        case 8: segments[0]=1; segments[1]=1; segments[2]=1; segments[3]=1; segments[4]=1; segments[5]=1; segments[6]=1; break;
        case 9: segments[0]=1; segments[1]=1; segments[2]=1; segments[3]=1; segments[5]=1; segments[6]=1; break;
        default: break;
    }
    
    // Draw segments
    if (segments[0]) { // Top
        for (int i = 0; i < 3; i++) matrix->setPixelOriented(x + i, y, color);
    }
    if (segments[1]) { // Top left
        matrix->setPixelOriented(x, y + 1, color);
        matrix->setPixelOriented(x, y + 2, color);
    }
    if (segments[2]) { // Top right
        matrix->setPixelOriented(x + 2, y + 1, color);
        matrix->setPixelOriented(x + 2, y + 2, color);
    }
    if (segments[3]) { // Middle
        for (int i = 0; i < 3; i++) matrix->setPixelOriented(x + i, y + 2, color);
    }
    if (segments[4]) { // Bottom left
        matrix->setPixelOriented(x, y + 3, color);
        matrix->setPixelOriented(x, y + 4, color);
    }
    if (segments[5]) { // Bottom right
        matrix->setPixelOriented(x + 2, y + 3, color);
        matrix->setPixelOriented(x + 2, y + 4, color);
    }
    if (segments[6]) { // Bottom
        for (int i = 0; i < 3; i++) matrix->setPixelOriented(x + i, y + 4, color);
    }
}
