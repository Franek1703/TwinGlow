#pragma once
#define CONFIG_H
#include "Arduino.h"
using std::max;
inline void delay(unsigned long ms) { fakeMillis += ms; }
inline void delayMicroseconds(unsigned long) {}
struct EspMock {
    unsigned restarts = 0;
    unsigned getFreeHeap() { return 120000; }
    unsigned getMaxAllocHeap() { return 110000; }
    void restart() { ++restarts; }
};
inline EspMock ESP;
#define MATRIX_WIDTH 16
#define MATRIX_HEIGHT 16
#define NEOPIXEL_PIN 2
#define NEOPIXEL_TYPE 0x52
#define DEFAULT_BRIGHTNESS 128
#define GAMMA_CORRECTION 1
#define GAMMA_EXPONENT 2.2f
#define PANEL_ORIENT_NONE 0
#define PANEL_ORIENT_ROT90 1
#define PANEL_ORIENT_ROT180 2
#define PANEL_ORIENT_ROT270 3
#define PANEL_ORIENT_TRANSPOSE 4
#define WIFI_RETRY_QUICK_COUNT 5
#define WIFI_RETRY_QUICK_DELAY_MS 4000
#define WIFI_RETRY_BACKOFF_MAX_MS 60000
#define WIFI_CONNECT_ATTEMPT_TIMEOUT_MS 10000
#define WIFI_TEARDOWN_SETTLE_MS 600
#define FIREBASE_OPERATION_WATCHDOG_MS 30000
#define FIREBASE_BRIGHTNESS_SETTLE_MS 1500
#define FIREBASE_ERROR_TCP_CONNECTION -1
