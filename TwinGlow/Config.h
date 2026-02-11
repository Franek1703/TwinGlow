/*
 * TwinGlow ESP32 Firmware - Configuration
 * 
 * CONFIGURATION CHECKLIST:
 * ========================
 * 1. Copy TwinGlow/FirebaseSecrets.h.example to TwinGlow/FirebaseSecrets.h (gitignored)
 * 2. In FirebaseSecrets.h set: FIREBASE_API_KEY, FIREBASE_DATABASE_URL,
 *    FIREBASE_DATABASE_SECRET, FIREBASE_PROJECT_ID (from Firebase Console)
 * 5. Verify hardware pins match your wiring:
 *    - NeoPixel data pin
 *    - Button GPIO pins
 *    - BME680 I2C pins (if using sensor)
 * 6. Adjust timing constants if needed (NTP sync interval, presence updates, etc.)
 * 
 * TROUBLESHOOTING:
 * ================
 * - TLS/Time errors: NTP sync failed -> check Wi-Fi connection, verify NTP servers accessible
 * - Wrong pins: NeoPixel not working -> verify NEOPIXEL_PIN matches your wiring
 * - BLE not advertising: Check BLE init, ensure device is not already provisioned
 * - NeoPixel flicker: Wi-Fi interrupts -> reduce rendering FPS, isolate rendering from network code
 * - Firebase auth fails: Verify API key, DB secret, ensure Authentication is enabled in Firebase Console
 * - Asset parsing fails: Check JSON format in Firestore, handle missing fields gracefully
 * - Wi-Fi keeps failing: Verify credentials, check signal strength, enter BLE provisioning mode
 */

#ifndef CONFIG_H
#define CONFIG_H

// FirebaseClient library build options (must be defined before any Firebase include in ALL .cpp units)
#define ENABLE_DATABASE      // Realtime Database
#define ENABLE_FIRESTORE     // Cloud Firestore
#define ENABLE_LEGACY_TOKEN  // Database secret auth

// Hardware pins
#define NEOPIXEL_PIN 2
#define MATRIX_WIDTH 16
#define MATRIX_HEIGHT 16
#define BUTTON_PREV_PIN 4
#define BUTTON_NEXT_PIN 5
#define BUTTON_BRIGHT_DOWN_PIN 18
#define BUTTON_BRIGHT_UP_PIN 19
#define BUTTON_ACTION_PIN 21
#define BME680_SDA_PIN 22
#define BME680_SCL_PIN 23
#define BME680_I2C_ADDR 0x76

// Firebase secrets (copy FirebaseSecrets.h.example to FirebaseSecrets.h and fill in)
#include "FirebaseSecrets.h"

// Timing constants
#define NTP_SYNC_INTERVAL_MS 21600000      // 6 hours
#define PRESENCE_UPDATE_INTERVAL_MS 20000  // 20 seconds
#define CONFIG_POLL_INTERVAL_MS 60000      // 60 seconds
#define TELEMETRY_UPDATE_INTERVAL_MS 10000 // 10 seconds (if BME680 present)
#define WIFI_RETRY_QUICK_COUNT 5
#define WIFI_RETRY_BACKOFF_MAX_MS 60000
#define WIFI_MAX_FAILURES 10

// Button timing
#define BUTTON_DEBOUNCE_MS 50
#define BUTTON_LONG_PRESS_MS 2500
#define BUTTON_VERY_LONG_PRESS_MS 10000

// NeoPixel settings
#define NEOPIXEL_TYPE NEO_GRB + NEO_KHZ800
#define DEFAULT_BRIGHTNESS 128

// BLE Configuration
#define BLE_DEVICE_NAME "TwinGlow"
#define BLE_SERVICE_UUID "0000ff00-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_SSID_UUID "0000ff01-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_PASS_UUID "0000ff02-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_UID_UUID "0000ff03-0000-1000-8000-00805f9b34fb"

// NVS Keys
#define NVS_NAMESPACE "twinglow"
#define NVS_KEY_WIFI_SSID "wifi_ssid"
#define NVS_KEY_WIFI_PASS "wifi_pass"
#define NVS_KEY_DEVICE_ID "device_id"
#define NVS_KEY_CLAIMED_UID "claimed_uid"
#define NVS_KEY_PROVISIONED "provisioned"
#define NVS_KEY_BRIGHTNESS "brightness"

// Firmware version
#define FW_VERSION "1.0.0"

// Set to 1 to run RTDB/Firestore put-get test once after Firebase connects
#define FIREBASE_RUN_TEST 0

#endif // CONFIG_H
