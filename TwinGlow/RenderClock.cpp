#include "RenderClock.h"
#include "Config.h"
#include "PixelFont.h"

// Digit patterns live in PixelFont so RenderSensor can draw from the same data.
// Used for leading-zero suppression in drawPatternDigit().
static const uint8_t blank[27] = {
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0
};

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
    
    // Render based on layout
    if (layout == "BIG_HHMM") {
        renderBigHHMM(hour, minute, fgColor, accentColor, bgColor, blinkColon);
    } else if (layout == "HHMM_PLUS_SECONDS_BAR") {
        renderHHMMPlusSecondsBar(hour, minute, second, fgColor, accentColor, bgColor, blinkColon);
    } else if (layout == "MINIMAL") {
        renderMinimal(hour, minute, fgColor, accentColor, bgColor, blinkColon);
    } else {
        // Default to BIG_HHMM
        renderBigHHMM(hour, minute, fgColor, accentColor, bgColor, blinkColon);
    }
    
    matrix->show();
}

void RenderClock::renderBigHHMM(int hour, int minute, uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon) {
    // Draw HH:MM - digits are 3 pixels wide, no spacing
    // First digit starts at x=0, second at x=3, colon at x=6, minutes at x=8 and x=11
    drawDigit(0, 4, hour / 10, fgColor);
    drawDigit(4, 4, hour % 10, fgColor);
    drawColon(7, 5, accentColor, blinkColon);
    drawDigit(9, 4, minute / 10, fgColor);
    drawDigit(13, 4, minute % 10, fgColor);
}

void RenderClock::renderHHMMPlusSecondsBar(int hour, int minute, int second, uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon) {
    // Draw HH:MM - digits are 3 pixels wide, no spacing
    // First digit starts at x=0, second at x=3, colon at x=6, minutes at x=8 and x=11
    drawDigit(0, 4, hour / 10, fgColor);
    drawDigit(4, 4, hour % 10, fgColor);
    drawColon(7, 5, accentColor, blinkColon);
    drawDigit(9, 4, minute / 10, fgColor);
    drawDigit(13, 4, minute % 10, fgColor);
    
    // Draw seconds bar at bottom
    drawSecondsBar(second, accentColor);
}

void RenderClock::renderMinimal(int hour, int minute, uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon) {
    // Smaller digits
    drawDigit(2, 6, hour / 10, fgColor);
    drawDigit(6, 6, hour % 10, fgColor);
    drawColon(10, 7, accentColor, blinkColon);
    drawDigit(12, 6, minute / 10, fgColor);
    drawDigit(14, 6, minute % 10, fgColor);
}

void RenderClock::drawPatternPixel(uint8_t patternX, uint8_t patternY, uint8_t baseX, uint8_t baseY, uint32_t color) {
    // Calculate absolute position
    uint8_t absX = baseX + patternX;
    uint8_t absY = baseY + patternY;
    
    // Draw pixel at rotated position
    matrix->setPixel(absY, absX, color);
}

void RenderClock::drawPatternDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color) {
    if (digit > 9) return;
    
    const uint8_t* pattern;
    if (digit == 0 && x == 0 && y == 0) {
        pattern = blank; // Special case for leading zero
    } else {
        pattern = PixelFont::digitBig(digit);
        if (pattern == nullptr) return;
    }
    
    // Draw 3x9 pattern (3 columns, 9 rows)
    for (uint8_t row = 0; row < 9; row++) {
        for (uint8_t col = 0; col < 3; col++) {
            if (pattern[(row * 3) + col] == 1) {
                drawPatternPixel(col, row, x, y, color);
            }
        }
    }
}

void RenderClock::drawDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color) {
    // Use pattern-based rendering with rotation
    drawPatternDigit(x, y, digit, color);
}

void RenderClock::drawColon(uint8_t x, uint8_t y, uint32_t color, bool blink) {
    if (blink && (millis() / 500) % 2 == 0) {
        return; // Blink off
    }
    
    // Draw colon as two 2x2 pixel segments (no spacing)
    // Top segment: 2x2 pixels at (x, y) to (x+1, y+1)
    // Bottom segment: 2x2 pixels at (x, y+3) to (x+1, y+4)
    for (uint8_t dx = 0; dx < 2; dx++) {
        for (uint8_t dy = 0; dy < 2; dy++) {
            // Top segment
            uint8_t absX = x + dx;
            uint8_t absY = y + dy;
            uint8_t rotatedX = (uint8_t)(MATRIX_WIDTH - 1 - absY);
            uint8_t rotatedY = absX;
            matrix->setPixel(rotatedX, rotatedY, color);
            
            // Bottom segment
            absY = y + 3 + dy;
            rotatedX = (uint8_t)(MATRIX_WIDTH - 1 - absY);
            rotatedY = absX;
            matrix->setPixel(rotatedX, rotatedY, color);
        }
    }
}

void RenderClock::drawSecondsBar(uint8_t seconds, uint32_t color) {
    // Draw progress bar at bottom (row 15)
    // After rotation: bottom row becomes leftmost column
    int pixels = (seconds * 16) / 60;
    for (int i = 0; i < pixels && i < 16; i++) {
        // Original: (i, 15) -> Rotated: (15-15, i) = (0, i)
        uint8_t rotX = 0;
        uint8_t rotY = (uint8_t)i;
        matrix->setPixel(rotX, rotY, color);
    }
}

void RenderClock::draw7Segment(uint8_t x, uint8_t y, uint8_t digit, uint32_t color) {
    // Simplified 7-segment rendering for 16x16 matrix
    // Each digit is 3x5 pixels
    // Basic patterns for digits 0-9
    
    // Clear digit area first
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 5; j++) {
            matrix->setPixel(x + i, y + j, 0); // Black
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
        for (int i = 0; i < 3; i++) matrix->setPixel(x + i, y, color);
    }
    if (segments[1]) { // Top left
        matrix->setPixel(x, y + 1, color);
        matrix->setPixel(x, y + 2, color);
    }
    if (segments[2]) { // Top right
        matrix->setPixel(x + 2, y + 1, color);
        matrix->setPixel(x + 2, y + 2, color);
    }
    if (segments[3]) { // Middle
        for (int i = 0; i < 3; i++) matrix->setPixel(x + i, y + 2, color);
    }
    if (segments[4]) { // Bottom left
        matrix->setPixel(x, y + 3, color);
        matrix->setPixel(x, y + 4, color);
    }
    if (segments[5]) { // Bottom right
        matrix->setPixel(x + 2, y + 3, color);
        matrix->setPixel(x + 2, y + 4, color);
    }
    if (segments[6]) { // Bottom
        for (int i = 0; i < 3; i++) matrix->setPixel(x + i, y + 4, color);
    }
}
