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
// NOTE: If your matrix doesn't work, try changing NEOPIXEL_PIN to 5 (common alternative)
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
#define NTP_SYNC_INTERVAL_MS 21600000      // 6 hours (after a successful sync)
#define NTP_RETRY_INTERVAL_MS 300000       // 5 minutes (while the clock is unsynced)
#define NTP_WAIT_MS 8000                   // How long one sync attempt waits for the first NTP packet
#define TIME_SYNC_STATE_TIMEOUT_MS 45000   // Hard deadline for the TIME_SYNC state before continuing unsynced
#define TIME_SYNC_RECONFIG_INTERVAL_MS 15000 // How often TIME_SYNC re-issues configTzTime() while waiting

// POSIX TZ rule applied until the app writes one to the device doc. "UTC0" keeps
// the pre-timezone behaviour rather than guessing a zone the owner may not be in.
#define DEFAULT_TZ_POSIX "UTC0"
#define PRESENCE_UPDATE_INTERVAL_MS 20000  // 20 seconds
#define CONFIG_POLL_INTERVAL_MS 60000      // 60 seconds
#define TELEMETRY_UPDATE_INTERVAL_MS 10000 // 10 seconds (if BME680 present)
// SENSOR screen
#define SENSOR_CYCLE_MS 2500             // AUTO_CYCLE dwell time per metric

// Shown instead of black when an asset fails to load or has an unknown
// encoding, so a broken screen is visibly different from a dark image.
#define ASSET_ERROR_COLOR 0x200000       // Dim red

// The panel is mounted turned, so the procedural screens transform as they
// draw. Assets are authored in plain orientation (x = column, y = row) and
// need the same treatment, or an IMAGE lands 90 degrees off from the CLOCK.
//   1 = transpose, setPixel(y, x)          - matches RenderClock's digits
//   0 = 90-degree rotation, setPixel(W-1-y, x) - matches its colon/seconds bar
// Those two differ by a mirror. Switch to 0 if images come out mirrored.
#define ASSET_ORIENT_TRANSPOSE 1

// Screen playlist rotation
#define SCREEN_AUTO_ROTATE 0             // 1 = cycle screens automatically, 0 = buttons only
#define SCREEN_DEFAULT_DURATION_MS 8000  // Used when a screen doc has no durationMs
#define SCREEN_MIN_DURATION_MS 2000      // Floor, so a bad value cannot spin the playlist

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
#define NVS_KEY_TZ_POSIX "tz_posix"

// Firmware version
#define FW_VERSION "1.0.0"

// Set to 1 to run RTDB/Firestore put-get test once after Firebase connects
#define FIREBASE_RUN_TEST 0

#endif // CONFIG_H
