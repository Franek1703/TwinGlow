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
#define CONFIG_POLL_INTERVAL_MS 60000      // 60 seconds (Firestore fallback poll)

// The ESP32 secure client defaults to a 120 second TLS handshake timeout.
// FirebaseClient's "async" API still calls that synchronous handshake, so a
// dead route can otherwise stop the Arduino loop (including button scanning)
// for up to two minutes. Periodic cloud work runs on a worker task as well,
// but bounded timeouts also protect boot/config-reload operations.
#define FIREBASE_TCP_CONNECT_TIMEOUT_MS 5000
// BearSSL buffers, replacing mbedTLS's 16KB receive buffer. RX must still hold
// one whole TLS record, so this is the first number to raise if handshakes
// start failing; every 1KB here costs a contiguous KB the asset fetches need.
#define FIREBASE_TLS_RX_BUFFER_BYTES 4096
#define FIREBASE_TLS_TX_BUFFER_BYTES 1024
#define FIREBASE_TLS_HANDSHAKE_TIMEOUT_SEC 8
#define FIREBASE_SYNC_IO_TIMEOUT_SEC 10

// How long the brightness buttons must sit still before the value is written
// back to Firestore. Each step is its own press, so a run of them used to queue
// a write, then re-queue a correction the moment that write returned - several
// document patches, each one a fresh TLS handshake, for a single adjustment the
// owner experienced as one gesture. Waiting for the panel to settle sends only
// the value it ends on.
#define FIREBASE_BRIGHTNESS_SETTLE_MS 1500

// Stuck-operation watchdog. Every transport timeout above is <= 10 s, so a job
// still running well past this point is wedged inside the library rather than
// merely slow. Nothing else ever times out an in-flight operation: jobPending
// is cleared only when a result comes back, so one hung call silences the
// presence tick and the config poll permanently while rendering continues.
#define FIREBASE_OPERATION_WATCHDOG_MS 30000
// A blocked worker call cannot be cancelled from outside, so past this the
// only way back to working cloud I/O is a restart.
#define FIREBASE_OPERATION_STUCK_REBOOT_MS 180000

// Runtime transport recovery. Two consecutive failures are treated as a dead
// path even when WiFi.status() still says WL_CONNECTED. The worker closes the
// stale TLS socket, cycles the station connection, and backs off before trying
// again so local playback and buttons continue normally.
#define FIREBASE_FAILURES_BEFORE_RECOVERY 2
// A TLS handshake needs one large contiguous block. Below this, repeated
// transport failures are a heap problem wearing a network problem's error code.
#define FIREBASE_TLS_MIN_BLOCK_BYTES 20000
#define FIREBASE_RECOVERY_BACKOFF_INITIAL_MS 30000
#define FIREBASE_RECOVERY_BACKOFF_MAX_MS 300000
// RTDB "doorbell" check. The app ticks /config/{deviceId}/configVersion on every
// config change; seeing it move makes the device run the Firestore check straight
// away instead of waiting out CONFIG_POLL_INTERVAL_MS.
//
// Disabled by default. Measured on hardware 2026-08-29: with the old synchronous
// poll active, the device ran clean for about a minute after boot, then hit
// "TCP connection failed" on presence AND Firestore and never recovered - the
// render loop stalled for 74 s at a stretch, repeatedly. The same build with the
// poll off is stable indefinitely (presence every 20 s, render every 5 s, no
// errors), so this is the cause, not the network.
//
// Why: FirebaseClientWrap shares ONE WiFiClientSecure and ONE AsyncClientClass
// between RTDB and Firestore, and every call is blocking. This is also the only
// production use of rtdb->get<>() - presence and telemetry only set/push. Once
// any transient error occurs, re-issuing a blocking read every 5 s never leaves
// the client room to re-establish, so a momentary failure becomes permanent.
//
// CloudWorker now serializes this read with every other Firebase operation,
// runs it away from loop(), and applies transport reset/backoff on failure.
// Keep it off until that recovery path has completed an on-device soak test;
// the 60-second Firestore fallback remains active either way.
#define ENABLE_RTDB_DOORBELL 0
#define REVISION_POLL_INTERVAL_MS 5000     // 5 seconds (only used when enabled)
#define TELEMETRY_UPDATE_INTERVAL_MS 10000 // 10 seconds (if BME680 present)
// SENSOR screen
#define SENSOR_CYCLE_MS 2500             // AUTO_CYCLE dwell time per metric

// Shown instead of black when an asset fails to load or has an unknown
// encoding, so a broken screen is visibly different from a dark image.
// Gamma correction crushes low values (0x20 -> 2/255, invisible), so this is
// authored bright enough to survive it while staying clearly dimmer than a
// real red screen.
#define ASSET_ERROR_COLOR 0x800000       // Dim red

// The panel is mounted turned, so everything authored in plain screen
// coordinates (x = column, y = row, origin top-left) has to be transformed on
// its way to the LEDs. That transform lives in exactly one place -
// MatrixDriver::setPixelOriented() - and every renderer draws through it. The
// clock digits, the colon, the seconds bar, the sensor text and image assets
// each used to carry their own inline version, which is how they drifted into
// mutually mirrored frames.
//   PANEL_ORIENT_NONE       (x, y)           panel mounted upright
//   PANEL_ORIENT_ROT90      (W-1-y, x)       90 degrees
//   PANEL_ORIENT_ROT180     (W-1-x, H-1-y)
//   PANEL_ORIENT_ROT270     (y, H-1-x)
//   PANEL_ORIENT_TRANSPOSE  (y, x)           ROT90 mirrored - the mapping the
//                                            digits and image assets have used
// This one value turns the whole display: change it if the screen comes out
// rotated, and pick the mirrored partner of your rotation if it comes out
// mirrored (TRANSPOSE mirrors ROT90).
#define PANEL_ORIENT_NONE      0
#define PANEL_ORIENT_ROT90     1
#define PANEL_ORIENT_ROT180    2
#define PANEL_ORIENT_ROT270    3
#define PANEL_ORIENT_TRANSPOSE 4

#define PANEL_ORIENTATION PANEL_ORIENT_TRANSPOSE

// Verbose asset-fetch instrumentation. Dumps the first 1000 characters of the
// Firestore response and a hex dump of its first 200 bytes on every getAsset().
// At 115200 baud that is roughly 200 ms of blocking serial per call - enough to
// perturb the timing it is meant to measure - so it stays off unless an asset
// fetch is actually being investigated.
#define FIRESTORE_DEBUG_ASSETS 0

// Frame budgets: how often each screen type is repainted.
//
// Every show() holds interrupts off for roughly 7.6 ms across 256 WS2812s, so
// repainting once per loop() pass (~100 fps) spends most of the CPU pushing
// identical pixels down the wire - and it is the flicker the troubleshooting
// notes at the top of this file describe, because the repaint contends with
// Wi-Fi work. A screen is repainted at the rate its content actually changes;
// a screen change always paints immediately.
#define FRAME_INTERVAL_CLOCK_MS 1000       // the seconds bar moves once a second
#define FRAME_INTERVAL_CLOCK_BLINK_MS 250  // a blinking colon toggles twice a second
#define FRAME_INTERVAL_SENSOR_MS 500       // value refresh and the AUTO_CYCLE switch
#define FRAME_INTERVAL_ANIMATION_MS 33     // ~30 fps ceiling; frame timing is the asset's
#define FRAME_INTERVAL_IMAGE_MS 200        // static, but catches a late-arriving asset
#define FRAME_INTERVAL_DEFAULT_MS 500      // placeholder patterns

// Screen playlist rotation
#define SCREEN_AUTO_ROTATE 0             // 1 = cycle screens automatically, 0 = buttons only
#define SCREEN_DEFAULT_DURATION_MS 8000  // Used when a screen doc has no durationMs
#define SCREEN_MIN_DURATION_MS 2000      // Floor, so a bad value cannot spin the playlist

#define WIFI_RETRY_QUICK_COUNT 5
#define WIFI_RETRY_QUICK_DELAY_MS 4000   // Consumer APs rate-limit a client that
                                         // re-auths every second, which turns a
                                         // transient drop into a lockout
#define WIFI_RETRY_BACKOFF_MAX_MS 60000
#define WIFI_MAX_FAILURES 10
#define WIFI_CONNECT_ATTEMPT_TIMEOUT_MS 10000
#define WIFI_TEARDOWN_SETTLE_MS 600      // Radio-off settle before re-associating
#define WIFI_OFFLINE_REBOOT_MS 720000    // 12 min offline after a good connection
                                         // means the station is wedged; reboot

// Button timing
#define BUTTON_DEBOUNCE_MS 50
#define BUTTON_LONG_PRESS_MS 2500
#define BUTTON_VERY_LONG_PRESS_MS 10000

// NeoPixel settings
#define NEOPIXEL_TYPE NEO_GRB + NEO_KHZ800
#define DEFAULT_BRIGHTNESS 128

// Sleep mode: the app sets a nightly window during which the panel drops to a
// dim level. 10/255 reads as a night light rather than a lamp; 0 blanks the
// panel entirely, which is the only way to turn it off (setBrightness clamps
// 0 up to 1).
#define DEFAULT_SLEEP_BRIGHTNESS 10
// How often the window is re-evaluated. Purely local - localtime() and an
// integer compare, no network - so this is unrelated to the Firestore poll.
#define SLEEP_CHECK_INTERVAL_MS 15000

// The app sends gamma-encoded sRGB (what the phone screen shows), but NeoPixel
// drives the byte out as a raw PWM duty cycle. Without correction every
// secondary channel emits several times too much light: the app's red preset
// (Material #F44336) put ~5x too much green and ~6.5x too much blue on the
// panel, so it read as pink/purple. MatrixDriver applies this to every pixel.
#define GAMMA_CORRECTION 1     // 0 = raw PWM (previous behaviour), for A/B testing
#define GAMMA_EXPONENT 2.2f    // sRGB. Try 2.6 if the panel still looks washed out.

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
#define NVS_KEY_SLEEP_ENABLED "sleep_en"
#define NVS_KEY_SLEEP_START "sleep_start"
#define NVS_KEY_SLEEP_END "sleep_end"
#define NVS_KEY_SLEEP_BRIGHT "sleep_bri"

// Firmware version
#define FW_VERSION "1.0.0"

// Set to 1 to run RTDB/Firestore put-get test once after Firebase connects
#define FIREBASE_RUN_TEST 0

#endif // CONFIG_H
