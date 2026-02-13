#ifndef RENDER_CLOCK_H
#define RENDER_CLOCK_H

#include "MatrixDriver.h"
#include <time.h>

/**
 * Clock screen renderer
 * Procedural rendering using local time
 */
class RenderClock {
public:
    RenderClock(MatrixDriver* matrix);
    
    void render(const String& format, const String& layout, 
                uint32_t fgColor, uint32_t accentColor, uint32_t bgColor,
                bool showSeconds, bool blinkColon);
    
private:
    MatrixDriver* matrix;
    
    void renderBigHHMM(uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon);
    void renderHHMMPlusSecondsBar(uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon);
    void renderMinimal(uint32_t fgColor, uint32_t accentColor, uint32_t bgColor, bool blinkColon);
    
    void drawDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color);
    void drawColon(uint8_t x, uint8_t y, uint32_t color, bool blink);
    void drawSecondsBar(uint8_t seconds, uint32_t color);
    
    // Pattern-based digit rendering (3x9 patterns) with rotation support
    void drawPatternDigit(uint8_t x, uint8_t y, uint8_t digit, uint32_t color);
    void drawPatternPixel(uint8_t patternX, uint8_t patternY, uint8_t baseX, uint8_t baseY, uint32_t color);
    
    // 7-segment digit patterns (simplified for 16x16) - legacy
    void draw7Segment(uint8_t x, uint8_t y, uint8_t digit, uint32_t color);
};

#endif // RENDER_CLOCK_H
