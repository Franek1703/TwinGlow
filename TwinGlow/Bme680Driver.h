#ifndef BME680_DRIVER_H
#define BME680_DRIVER_H

#include <Adafruit_BME680.h>
#include "Config.h"
#include <Arduino.h>

/**
 * BME680 sensor driver
 * Handles initialization and reading
 */
class Bme680Driver {
public:
    Bme680Driver();
    ~Bme680Driver();
    
    bool begin();
    bool isPresent() const { return present; }
    
    // Reading
    bool read(float& temperature, float& humidity, float& pressure, float& gas);
    
    // Unit conversion
    float celsiusToFahrenheit(float celsius) const { return celsius * 9.0 / 5.0 + 32.0; }
    float hectopascalToInchHg(float hpa) const { return hpa * 0.0295299830714; }
    
private:
    Adafruit_BME680* sensor;
    bool present;
    
    bool detect();
};

#endif // BME680_DRIVER_H
