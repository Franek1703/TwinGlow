#ifndef PIXEL_FONT_H
#define PIXEL_FONT_H

#include <Arduino.h>

/**
 * Shared bitmap glyphs for the procedural renderers.
 *
 * Every pattern is row-major and one byte per pixel: pattern[row * width + col],
 * where 1 means lit. Kept in one place so RenderClock and RenderSensor draw from
 * the same data instead of each carrying a private copy.
 *
 * Patterns are stored in plain display orientation (x = column, y = row). Any
 * rotation is the caller's business.
 */
namespace PixelFont {

// Large digits, used for the clock and for short sensor values.
static const uint8_t DIGIT_BIG_W = 3;
static const uint8_t DIGIT_BIG_H = 9;
static const uint8_t DIGIT_BIG_ADVANCE = DIGIT_BIG_W + 1; // 1px inter-glyph gap

// Small glyphs, used for labels, units and values too wide for the big digits.
static const uint8_t GLYPH_W = 3;
static const uint8_t GLYPH_H = 5;
static const uint8_t GLYPH_ADVANCE = GLYPH_W + 1; // 1px inter-glyph gap

// 3x9 pattern for '0'-'9'. Returns nullptr when digit > 9.
const uint8_t* digitBig(uint8_t digit);

// 3x5 pattern for '0'-'9', 'A'-'Z' (lowercase is folded to upper), '%', '.',
// '-' and ' '. Returns nullptr when the character has no glyph.
const uint8_t* glyph(char c);

// Rendered width of `text` in the 3x5 font, including inter-glyph gaps.
uint8_t textWidth(const String& text);

// Rendered width of `digits` in the 3x9 font, including inter-glyph gaps.
uint8_t digitsBigWidth(const String& digits);

} // namespace PixelFont

#endif // PIXEL_FONT_H
