#include "Bme680Driver.h"
#include <Wire.h>

Bme680Driver::Bme680Driver() : sensor(nullptr), present(false) {
}

Bme680Driver::~Bme680Driver() {
    if (sensor != nullptr) {
        delete sensor;
    }
}

bool Bme680Driver::begin() {
    Serial.println("[BME680] Initializing...");
    
    if (!detect()) {
        Serial.println("[BME680] Sensor not detected");
        present = false;
        return false;
    }
    
    present = true;
    Serial.println("[BME680] Sensor detected and initialized");
    return true;
}

bool Bme680Driver::detect() {
    Wire.begin(BME680_SDA_PIN, BME680_SCL_PIN);
    
    sensor = new Adafruit_BME680(&Wire);
    
    if (!sensor->begin(BME680_I2C_ADDR)) {
        delete sensor;
        sensor = nullptr;
        return false;
    }
    
    // Configure sensor (Adafruit BME680 API)
    sensor->setTemperatureOversampling(BME680_OS_16X);
    sensor->setHumidityOversampling(BME680_OS_16X);
    sensor->setPressureOversampling(BME680_OS_16X);
    sensor->setIIRFilterSize(BME680_FILTER_SIZE_3);
    sensor->setGasHeater(320, 150); // 320°C for 150 ms
    
    return true;
}

bool Bme680Driver::read(float& temperature, float& humidity, float& pressure, float& gas) {
    if (!present || sensor == nullptr) {
        return false;
    }
    
    if (!sensor->performReading()) {
        Serial.println("[BME680] Failed to read sensor");
        return false;
    }
    
    temperature = sensor->temperature;
    humidity = sensor->humidity;
    pressure = sensor->pressure / 100.0f; // Convert Pa to hPa (pressure is uint32_t)
    gas = (float)sensor->gas_resistance;
    
    return true;
}
