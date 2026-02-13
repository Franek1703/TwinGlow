#include "RenderClock.h"

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
    
    struct tm* timeinfo = localtime(&now);
    if (timeinfo == nullptr) {
        matrix->fill(matrix->color(255, 0, 0)); // Red
        matrix->show();
        return;
    }
    
    int hour = timeinfo->tm_hour;
    int minute = timeinfo->tm_min;
    int second = timeinfo->tm_sec;
    
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
        renderBigHHMM(fgColor, accentColor, bgColor, blinkColon);
    } else if (layout == "HHMM_PLUS_SECONDS_BAR") {
        renderHHMMPlusSecondsBar(fgColor, accentColor, bgColor, blinkColon);
    } else if (layout == "MINIMAL") {
        renderMinimal(fgColor, accentColor, bgColor, blinkColon);
    } else {
        // Default to BIG_HHMM
        renderBigHHMM(fgColor, accentColor, bgColor, blinkColon);
    }
    
    matrix->show();
}

void RenderClock::renderBigHHMM(uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon) {
    time_t now = time(nullptr);
    struct tm* timeinfo = localtime(&now);
    int hour = timeinfo->tm_hour;
    int minute = timeinfo->tm_min;
    
    // Draw HH:MM
    drawDigit(1, 4, hour / 10, fgColor);
    drawDigit(5, 4, hour % 10, fgColor);
    drawColon(9, 6, accentColor, blinkColon);
    drawDigit(11, 4, minute / 10, fgColor);
    drawDigit(15, 4, minute % 10, fgColor);
}

void RenderClock::renderHHMMPlusSecondsBar(uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon) {
    time_t now = time(nullptr);
    struct tm* timeinfo = localtime(&now);
    int hour = timeinfo->tm_hour;
    int minute = timeinfo->tm_min;
    int second = timeinfo->tm_sec;
    
    // Draw HH:MM
    drawDigit(1, 4, hour / 10, fgColor);
    drawDigit(5, 4, hour % 10, fgColor);
    drawColon(9, 6, accentColor, blinkColon);
    drawDigit(11, 4, minute / 10, fgColor);
    drawDigit(15, 4, minute % 10, fgColor);
    
    // Draw seconds bar at bottom
    drawSecondsBar(second, accentColor);
}

void RenderClock::renderMinimal(uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon) {
    time_t now = time(nullptr);
    struct tm* timeinfo = localtime(&now);
    int hour = timeinfo->tm_hour;
    int minute = timeinfo->tm_min;
    
    // Smaller digits
    drawDigit(2, 6, hour / 10, fgColor);
    drawDigit(6, 6, hour % 10, fgColor);
    drawColon(10, 7, accentColor, blinkColon);
    drawDigit(12, 6, minute / 10, fgColor);
    drawDigit(14, 6, minute % 10, fgColor);
}

void RenderClock::drawDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color) {
    // Simplified digit rendering - draw basic patterns
    // For a full implementation, use 7-segment or bitmap fonts
    draw7Segment(x, y, digit, color);
}

void RenderClock::drawColon(uint8_t x, uint8_t y, uint32_t color, bool blink) {
    if (blink && (millis() / 500) % 2 == 0) {
        return; // Blink off
    }
    
    matrix->setPixel(x, y, color);
    matrix->setPixel(x, y + 2, color);
}

void RenderClock::drawSecondsBar(uint8_t seconds, uint32_t color) {
    // Draw progress bar at bottom (row 15)
    int pixels = (seconds * 16) / 60;
    for (int i = 0; i < pixels && i < 16; i++) {
        matrix->setPixel(i, 15, color);
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
