#include "RenderSensor.h"

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
    float value = 0.0;
    String unit = "";
    String label = "";
    
    if (currentMetric == "temperature") {
        value = temperature;
        unit = (units == "IMPERIAL") ? "F" : "C";
        label = "TEMP";
    } else if (currentMetric == "humidity") {
        value = humidity;
        unit = "%";
        label = "HUM";
    } else if (currentMetric == "pressure") {
        value = pressure;
        unit = (units == "IMPERIAL") ? "inHg" : "hPa";
        label = "PRS";
    }
    
    // Render based on layout
    if (layout == "BIG_VALUE_WITH_LABEL") {
        renderBigValueWithLabel(fgColor, accentColor, label, value, unit);
    } else if (layout == "VALUE_WITH_BAR") {
        float maxValue = (currentMetric == "humidity") ? 100.0 : 50.0;
        renderValueWithBar(fgColor, accentColor, label, value, maxValue);
    } else {
        // Default
        renderBigValueWithLabel(fgColor, accentColor, label, value, unit);
    }
    
    matrix->show();
}

void RenderSensor::renderBigValueWithLabel(uint32_t fgColor, uint32_t accentColor,
                                            const String& label, float value, const String& unit) {
    // Draw label at top
    drawLabel(2, 1, label, accentColor);
    
    // Draw value in center
    drawNumber(2, 6, value, fgColor);
    
    // Draw unit
    // Simplified - would need proper font rendering
}

void RenderSensor::renderValueWithBar(uint32_t fgColor, uint32_t accentColor,
                                      const String& label, float value, float maxValue) {
    drawLabel(2, 1, label, accentColor);
    drawNumber(2, 6, value, fgColor);
    
    // Draw bar
    float fillRatio = value / maxValue;
    if (fillRatio > 1.0) fillRatio = 1.0;
    drawBar(2, 12, 12, 3, fillRatio, accentColor);
}

void RenderSensor::drawNumber(uint8_t x, uint8_t y, float value, uint32_t color) {
    // Simplified number rendering
    // Convert float to string and draw digits
    String str = String((int)value);
    for (size_t i = 0; i < str.length() && i < 4; i++) {
        char c = str[i];
        if (c >= '0' && c <= '9') {
            // Draw digit at position
            // Simplified - would need proper font
        }
    }
}

void RenderSensor::drawLabel(uint8_t x, uint8_t y, const String& label, uint32_t color) {
    // Simplified label rendering
    // Would need proper font rendering for full implementation
}

void RenderSensor::drawBar(uint8_t x, uint8_t y, uint8_t width, uint8_t height, float fill, uint32_t color) {
    int fillPixels = (int)(width * fill);
    for (int i = 0; i < fillPixels && i < width; i++) {
        for (int j = 0; j < height && (y + j) < 16; j++) {
            matrix->setPixel(x + i, y + j, color);
        }
    }
}
