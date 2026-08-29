#include "RenderSensor.h"
#include "PixelFont.h"
#include <math.h>

// Vertical layout on the 16x16 panel:
//   rows 0-4    label      (3x5, accent)
//   row  5      gap
//   rows 6-14   value      (3x9 digits, foreground) - short values only
//   rows 8-12   value      (3x5, foreground)        - when it will not fit big
//   rows 12-14  bar        (VALUE_WITH_BAR layout)
static const uint8_t LABEL_Y      = 0;
static const uint8_t BIG_VALUE_Y  = 6;
static const uint8_t WIDE_VALUE_Y = 8;
static const uint8_t BAR_Y        = 12;
static const uint8_t BAR_H        = 3;

RenderSensor::RenderSensor(MatrixDriver* mat) : matrix(mat) {
}

void RenderSensor::render(const String& mode, const String& layout,
                         const std::vector<String>& showMetrics,
                         const String& units,
                         uint32_t fgColor, uint32_t accentColor, uint32_t bgColor,
                         float temperature, float humidity, float pressure, float gas,
                         int currentMetricIndex) {
    matrix->fill(bgColor);

    if (showMetrics.empty()) {
        matrix->show();
        return;
    }

    // Get current metric to display
    String currentMetric = showMetrics[currentMetricIndex % showMetrics.size()];
    bool imperial = (units == "IMPERIAL");
    float value = 0.0;
    float maxValue = 100.0;
    String unit = "";
    String label = "";

    if (currentMetric == "temperature") {
        // The unit label used to say F without converting the reading.
        value = imperial ? (temperature * 9.0f / 5.0f + 32.0f) : temperature;
        unit = imperial ? "F" : "C";
        label = "TEMP";
        maxValue = imperial ? 120.0 : 50.0;
    } else if (currentMetric == "humidity") {
        value = humidity;
        unit = "%";
        label = "HUM";
        maxValue = 100.0;
    } else if (currentMetric == "pressure") {
        // hPa -> inHg. "inHg" does not fit on 16px, so the short form is used.
        value = imperial ? (pressure * 0.02953f) : pressure;
        unit = imperial ? "IN" : "HPA";
        label = "PRS";
        maxValue = imperial ? 32.0 : 1100.0;
    } else {
        label = "GAS";
        value = gas / 1000.0f; // kOhm keeps it to a readable number of digits
        unit = "K";
        maxValue = 500.0;
    }

    // Render based on layout
    if (layout == "VALUE_WITH_BAR") {
        renderValueWithBar(fgColor, accentColor, label, value, maxValue);
    } else {
        // BIG_VALUE_WITH_LABEL and anything unrecognised
        renderBigValueWithLabel(fgColor, accentColor, label, value, unit);
    }

    matrix->show();
}

void RenderSensor::renderBigValueWithLabel(uint32_t fgColor, uint32_t accentColor,
                                            const String& label, float value, const String& unit) {
    drawTextCentered(LABEL_Y, label, accentColor);

    String digits = String((int)lroundf(value));

    // Two big digits plus a small unit is the widest that fits: 3+1+3 = 7px of
    // digits, a 2px gap, then up to 3px of unit. Anything longer (pressure in
    // hPa, a negative temperature) falls back to the small font.
    uint8_t bigW = PixelFont::digitsBigWidth(digits);
    uint8_t unitW = PixelFont::textWidth(unit);
    if (digits.length() <= 2 && bigW + 2 + unitW <= MATRIX_WIDTH) {
        int totalW = bigW + (unitW > 0 ? 2 + unitW : 0);
        int x = (MATRIX_WIDTH - totalW) / 2;
        drawBigDigits(x, BIG_VALUE_Y, digits, fgColor);
        if (unitW > 0) {
            // Bottom-aligned against the 9px digits.
            drawText(x + bigW + 2, BIG_VALUE_Y + PixelFont::DIGIT_BIG_H - PixelFont::GLYPH_H,
                     unit, fgColor);
        }
        return;
    }

    // Wide value: drop the unit if the number alone already fills the row.
    String text = digits;
    if (PixelFont::textWidth(text + unit) <= MATRIX_WIDTH) {
        text += unit;
    }
    drawTextCentered(WIDE_VALUE_Y, text, fgColor);
}

void RenderSensor::renderValueWithBar(uint32_t fgColor, uint32_t accentColor,
                                      const String& label, float value, float maxValue) {
    drawTextCentered(LABEL_Y, label, accentColor);
    drawTextCentered(BIG_VALUE_Y, String((int)lroundf(value)), fgColor);

    float fillRatio = (maxValue > 0.0f) ? (value / maxValue) : 0.0f;
    if (fillRatio > 1.0f) fillRatio = 1.0f;
    if (fillRatio < 0.0f) fillRatio = 0.0f;
    drawBar(1, BAR_Y, MATRIX_WIDTH - 2, BAR_H, fillRatio, accentColor);
}

void RenderSensor::drawText(int x, uint8_t y, const String& text, uint32_t color) {
    int cursor = x;
    for (size_t i = 0; i < text.length(); i++) {
        const uint8_t* g = PixelFont::glyph(text[i]);
        if (g != nullptr) {
            for (uint8_t row = 0; row < PixelFont::GLYPH_H; row++) {
                for (uint8_t col = 0; col < PixelFont::GLYPH_W; col++) {
                    if (g[row * PixelFont::GLYPH_W + col] == 1) {
                        int px = cursor + col;
                        if (px >= 0 && px < MATRIX_WIDTH) {
                            matrix->setPixel((uint8_t)px, y + row, color);
                        }
                    }
                }
            }
        }
        cursor += PixelFont::GLYPH_ADVANCE;
        if (cursor >= MATRIX_WIDTH) break;
    }
}

void RenderSensor::drawTextCentered(uint8_t y, const String& text, uint32_t color) {
    int w = PixelFont::textWidth(text);
    int x = (MATRIX_WIDTH - w) / 2;
    if (x < 0) x = 0;
    drawText(x, y, text, color);
}

void RenderSensor::drawBigDigits(int x, uint8_t y, const String& digits, uint32_t color) {
    int cursor = x;
    for (size_t i = 0; i < digits.length(); i++) {
        char c = digits[i];
        if (c >= '0' && c <= '9') {
            const uint8_t* pattern = PixelFont::digitBig((uint8_t)(c - '0'));
            if (pattern != nullptr) {
                for (uint8_t row = 0; row < PixelFont::DIGIT_BIG_H; row++) {
                    for (uint8_t col = 0; col < PixelFont::DIGIT_BIG_W; col++) {
                        if (pattern[row * PixelFont::DIGIT_BIG_W + col] == 1) {
                            int px = cursor + col;
                            if (px >= 0 && px < MATRIX_WIDTH) {
                                matrix->setPixel((uint8_t)px, y + row, color);
                            }
                        }
                    }
                }
            }
        }
        cursor += PixelFont::DIGIT_BIG_ADVANCE;
        if (cursor >= MATRIX_WIDTH) break;
    }
}

void RenderSensor::drawBar(uint8_t x, uint8_t y, uint8_t width, uint8_t height, float fill, uint32_t color) {
    int fillPixels = (int)(width * fill + 0.5f);
    for (int i = 0; i < fillPixels && i < width; i++) {
        for (int j = 0; j < height && (y + j) < MATRIX_HEIGHT; j++) {
            matrix->setPixel(x + i, y + j, color);
        }
    }
}
