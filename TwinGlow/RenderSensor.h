#ifndef RENDER_SENSOR_H
#define RENDER_SENSOR_H

#include "MatrixDriver.h"
#include <vector>

/**
 * Sensor screen renderer (BME680)
 * Procedural rendering using live readings and cloud-provided presentation config
 */
class RenderSensor {
public:
    RenderSensor(MatrixDriver* matrix);

    void render(const String& mode, const String& layout,
                const std::vector<String>& showMetrics,
                const String& units,
                uint32_t fgColor, uint32_t accentColor, uint32_t bgColor,
                float temperature, float humidity, float pressure, float gas,
                int currentMetricIndex);

private:
    MatrixDriver* matrix;

    void renderBigValueWithLabel(uint32_t fgColor, uint32_t accentColor,
                                 const String& label, float value, const String& unit);
    void renderValueWithBar(uint32_t fgColor, uint32_t accentColor,
                            const String& label, float value, float maxValue);

    // 3x5 text
    void drawText(int x, uint8_t y, const String& text, uint32_t color);
    void drawTextCentered(uint8_t y, const String& text, uint32_t color);

    // 3x9 digits, for short values only
    void drawBigDigits(int x, uint8_t y, const String& digits, uint32_t color);

    void drawBar(uint8_t x, uint8_t y, uint8_t width, uint8_t height, float fill, uint32_t color);
};

#endif // RENDER_SENSOR_H
