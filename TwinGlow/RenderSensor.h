#ifndef RENDER_SENSOR_H
#define RENDER_SENSOR_H

#include "MatrixDriver.h"
#include <Arduino.h>

/**
 * Sensor screen renderer
 * Procedural rendering using BME680 readings
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
    
    void drawNumber(uint8_t x, uint8_t y, float value, uint32_t color);
    void drawLabel(uint8_t x, uint8_t y, const String& label, uint32_t color);
    void drawBar(uint8_t x, uint8_t y, uint8_t width, uint8_t height, float fill, uint32_t color);
};

#endif // RENDER_SENSOR_H
