/*
 * TwinGlow ESP32 Firmware
 * Complete firmware for 16x16 NeoPixel matrix device
 * 
 * See Config.h for configuration checklist and troubleshooting
 */

// Let FirebaseClient use external PSRAM (define before any Firebase include)
#define ENABLE_PSRAM

#include "Config.h"
#include "NvsStore.h"
#include "StateMachine.h"
#include "Scheduler.h"
#include "BleProvisioning.h"
#include "WifiManager.h"
#include "FirebaseClientWrap.h"
#include <ArduinoJson.h>
#include "FirestoreRepo.h"
#include "RtdbRepo.h"
#include "TimeSync.h"
#include "MatrixDriver.h"
#include "RenderClock.h"
#include "RenderSensor.h"
#include "RenderAsset.h"
#include "AssetCache.h"
#include "ScreenPlaylist.h"
#include "Buttons.h"
#include "ButtonActions.h"
#include "Bme680Driver.h"
#include "FirebaseTest.h"

// Fallback for a Config.h that predates this flag (it is listed in
// .gitignore, so local copies can drift from the tracked one).
// Default to manual-only screen changes; set to 1 in Config.h to auto-rotate.
#ifndef SCREEN_AUTO_ROTATE
#define SCREEN_AUTO_ROTATE 0
#endif

// Forward declaration
struct ScreenConfig;

// Global instances
NvsStore nvs;
StateMachine fsm;
Scheduler scheduler;
BleProvisioning bleProvisioning;
WifiManager wifiManager;
FirebaseClientWrap firebaseClient;
FirestoreRepo* firestoreRepo = nullptr;
RtdbRepo* rtdbRepo = nullptr;
TimeSync timeSync;
MatrixDriver matrix;
RenderClock renderClock(&matrix);
RenderSensor renderSensor(&matrix);
RenderAsset renderAsset(&matrix);
AssetCache assetCache;
ScreenPlaylist playlist;
Buttons buttons;
ButtonActions* buttonActions = nullptr;
Bme680Driver bme680;

// State variables
String deviceId;
String claimedUid;
int currentConfigVersion = -1;
bool bme680Present = false;
bool bme680Detected = false;
float sensorTemp = 0, sensorHumidity = 0, sensorPressure = 0, sensorGas = 0;
int sensorMetricIndex = 0;
unsigned long lastSensorReadMs = 0;

void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println(F("\n\n=== TwinGlow Firmware Starting ==="));
    Serial.print(F("FW Version: "));
    Serial.println(FW_VERSION);
    
    // Initialize state machine
    fsm.setState(DeviceState::BOOT);
    
    // Initialize matrix for visual feedback
    if (!matrix.begin()) {
        Serial.println(F("[ERROR] Matrix initialization failed - check NEOPIXEL_PIN in Config.h"));
        Serial.println(F("[ERROR] Common fixes: change NEOPIXEL_PIN to 5, check wiring, verify power"));
    } else {
        matrix.clear();
        // Test rainbow animation on startup
        Serial.println(F("[Matrix] Running startup test animation..."));
        matrix.testRainbow(2000); // 2 second rainbow animation
        matrix.clear();
        
        matrix.fill(matrix.color(0, 255, 255)); // Blue during boot
        matrix.show();
    }
    
    // Initialize NVS
    if (!nvs.begin()) {
        Serial.println(F("[ERROR] NVS initialization failed"));
        fsm.setError("NVS init failed");
        return;
    }
    
    fsm.transition(DeviceState::LOAD_NVS);
    
    // Load device ID
    if (!nvs.getDeviceId(deviceId)) {
        Serial.println(F("[ERROR] Failed to get device ID"));
        return;
    }
    Serial.print(F("[NVS] Device ID: "));
    Serial.println(deviceId);
    
    // Load brightness
    uint8_t brightness = nvs.getBrightness();
    matrix.setBrightness(brightness);

    // Load the cached timezone. TIME_SYNC runs long before Firestore is
    // readable, so without this the clock would show UTC for the first minute
    // of every boot - and forever if the device never gets back online.
    String cachedTz;
    if (nvs.getTzPosix(cachedTz)) {
        timeSync.setTimeZone(cachedTz);
    } else {
        Serial.print(F("[NVS] No cached timezone, defaulting to "));
        Serial.println(F(DEFAULT_TZ_POSIX));
    }

    // Check provisioning status
    if (!nvs.isProvisioned()) {
        Serial.println(F("[NVS] Not provisioned, entering BLE mode"));
        fsm.transition(DeviceState::PROVISIONING_BLE);
    } else {
        // Load Wi-Fi credentials
        String ssid, pass;
        if (nvs.getWifiSsid(ssid)) {
            nvs.getWifiPass(pass);
            Serial.print(F("[NVS] Wi-Fi SSID: "));
            Serial.println(ssid);
            fsm.transition(DeviceState::WIFI_CONNECTING);
        } else {
            Serial.println(F("[NVS] No Wi-Fi credentials, entering BLE mode"));
            fsm.transition(DeviceState::PROVISIONING_BLE);
        }
    }
    
    // Load claimed UID
    nvs.getClaimedUid(claimedUid);
    
    // Initialize buttons
    buttons.begin();
    
    Serial.println(F("[Setup] Complete"));
}

void loop() {
    // Update buttons
    buttons.update();
    
    // Handle button actions if initialized
    if (buttonActions != nullptr) {
        buttonActions->update();
    }
    
    // State machine
    switch (fsm.getState()) {
        case DeviceState::BOOT:
            // Already handled in setup()
            break;
            
        case DeviceState::LOAD_NVS:
            // Already handled in setup()
            break;
            
        case DeviceState::PROVISIONING_BLE:
            handleProvisioningBle();
            break;
            
        case DeviceState::WIFI_CONNECTING:
            handleWifiConnecting();
            break;
            
        case DeviceState::TIME_SYNC:
            handleTimeSync();
            break;
            
        case DeviceState::FIREBASE_CONNECTING:
            handleFirebaseConnecting();
            break;
            
        case DeviceState::DEVICE_CLAIMING:
            handleDeviceClaiming();
            break;
            
        case DeviceState::CAPABILITY_DETECT:
            handleCapabilityDetect();
            break;
            
        case DeviceState::CONFIG_LOADING:
            handleConfigLoading();
            break;
            
        case DeviceState::RUNNING:
            handleRunning();
            break;
            
        case DeviceState::OFFLINE_RUNNING:
            handleOfflineRunning();
            break;
            
        case DeviceState::ERROR_RECOVERY:
            handleErrorRecovery();
            break;
    }
    
    // Update scheduler
    scheduler.update();
    
    // Small delay to prevent watchdog issues
    delay(10);
}

void handleProvisioningBle() {
    static bool bleStarted = false;
    
    if (!bleStarted) {
        if (bleProvisioning.begin()) {
            bleStarted = true;
            matrix.fill(matrix.color(255, 255, 0)); // Yellow during provisioning
            matrix.show();
        } else {
            Serial.println(F("[BLE] Failed to start"));
            delay(1000);
        }
    }
    
    // Update BLE (handles disconnects)
    bleProvisioning.update();
    
    // Check if provisioning complete (after disconnect)
    if (!bleProvisioning.isAdvertising() && bleProvisioning.isProvisioningComplete()) {
        // Save credentials to NVS
        nvs.setWifiSsid(bleProvisioning.getSsid());
        nvs.setWifiPass(bleProvisioning.getPass());
        nvs.setClaimedUid(bleProvisioning.getUid());
        nvs.setProvisioned(true);

        // Keep the in-memory copy in step with NVS. setup() read claimedUid
        // before BLE had received anything, so without this the device reaches
        // DEVICE_CLAIMING with an empty UID, skips claiming, and never shows up
        // in the app. Redundant with the reboot below, but the handler should
        // not silently depend on it.
        claimedUid = bleProvisioning.getUid();

        Serial.println(F("[BLE] Provisioning complete, credentials saved"));

        matrix.fill(matrix.color(0, 255, 0)); // Green: provisioned
        matrix.show();
        delay(500);

        // Reboot, as the BLE provisioning protocol specifies. A clean boot
        // reloads NVS and brings up Wi-Fi/TLS with the BLE stack already
        // released, which is the largest single block of heap the Firebase
        // work has to fit around.
        Serial.println(F("[BLE] Rebooting to start provisioned"));
        Serial.flush();
        bleStarted = false;
        nvs.end();
        ESP.restart();
    }
}

void handleWifiConnecting() {
    static bool wifiStarted = false;
    
    if (!wifiStarted) {
        String ssid, pass;
        if (nvs.getWifiSsid(ssid)) {
            nvs.getWifiPass(pass);
            if (wifiManager.begin(ssid, pass)) {
                wifiStarted = true;
                // matrix.fill(matrix.color(0, 255, 0)); // Green during Wi-Fi
                matrix.show();
            }
        } else {
            Serial.println(F("[WiFi] No credentials, entering BLE mode"));
            fsm.transition(DeviceState::PROVISIONING_BLE);
            return;
        }
    }
    
    wifiManager.update();
    
    if (wifiManager.isConnected()) {
        Serial.println(F("[WiFi] Connected!"));
        wifiStarted = false;
        fsm.transition(DeviceState::TIME_SYNC);
    } else if (wifiManager.shouldEnterProvisioning()) {
            Serial.println(F("[WiFi] Too many failures, entering BLE mode"));
        wifiManager.reset();
        wifiStarted = false;
        fsm.transition(DeviceState::PROVISIONING_BLE);
    }
}

// Applies a timezone that arrived in the device doc. Empty means the doc has no
// timezone yet, in which case the cached one stays - a device that has been set
// up must not fall back to UTC just because the field went missing.
void applyTimeZone(const String& tzPosix) {
    if (tzPosix.length() == 0) return;
    if (tzPosix == timeSync.getTimeZone()) return;
    nvs.setTzPosix(tzPosix);
    timeSync.setTimeZone(tzPosix);
}

void handleTimeSync() {
    static unsigned long stateStartMs = 0;
    static unsigned long lastAttemptMs = 0;
    static uint8_t attempts = 0;

    // Per-entry reset, so re-entering TIME_SYNC retries instead of no-opping.
    // stateStartMs is set ONCE per entry - setting it every pass (as the old
    // code did) made the timeout below unreachable and stranded the device here.
    if (fsm.justEntered()) {
        stateStartMs = millis();
        lastAttemptMs = 0;
        attempts = 0;
    }

    // Checked first, every pass: the ESP32 SNTP client keeps running in the
    // background, so the clock can land between attempts even when the previous
    // sync() reported failure.
    if (TimeSync::isTimeValid()) {
        time_t now = time(nullptr);
        Serial.print(F("[TimeSync] Time valid, epoch="));
        Serial.println(now);
        timeSync.setSynced(true);
        firebaseClient.getApp()->setTime(now);
        fsm.transition(DeviceState::FIREBASE_CONNECTING);
        return;
    }

    // Hard deadline. Firebase may still fail TLS without a correct clock, in
    // which case FIREBASE_CONNECTING falls through to OFFLINE_RUNNING and the
    // scheduled NTP task keeps retrying every NTP_RETRY_INTERVAL_MS.
    if (millis() - stateStartMs >= TIME_SYNC_STATE_TIMEOUT_MS) {
        Serial.print(F("[TimeSync] Giving up after "));
        Serial.print(attempts);
        Serial.print(F(" attempts / "));
        Serial.print(millis() - stateStartMs);
        Serial.println(F("ms, continuing with unsynced clock"));
        fsm.transition(DeviceState::FIREBASE_CONNECTING);
        return;
    }

    // Space attempts out. Each sync() blocks for up to NTP_WAIT_MS, and
    // re-issuing configTime() restarts the SNTP client, so don't do it often.
    if (attempts > 0 && (millis() - lastAttemptMs) < TIME_SYNC_RECONFIG_INTERVAL_MS) return;

    attempts++;
    Serial.print(F("[TimeSync] Attempt "));
    Serial.println(attempts);
    timeSync.sync(firebaseClient.getApp());
    lastAttemptMs = millis();
    // Outcome is decided by the isTimeValid() check on the next pass.
}

void handleFirebaseConnecting() {
    // OFFLINE_RUNNING re-enters this state to retry, so the guard is per-entry.
    if (!fsm.justEntered()) return;

    if (firebaseClient.begin()) {
        // begin() is idempotent - only allocate the repos on the first success.
        if (firestoreRepo == nullptr) {
            firestoreRepo = new FirestoreRepo(
                &firebaseClient,
                FIREBASE_PROJECT_ID,
                deviceId
            );
        }
        if (rtdbRepo == nullptr) {
            rtdbRepo = new RtdbRepo(
                &firebaseClient,
                deviceId
            );
        }
        Serial.println(F("[Firebase] Connected"));
#if FIREBASE_RUN_TEST
        runFirebaseTest(firebaseClient);
#endif
        fsm.transition(DeviceState::DEVICE_CLAIMING);
    } else {
        Serial.println(F("[Firebase] Connection failed"));
        delay(2000);
        // Retry or go offline
        fsm.transition(DeviceState::OFFLINE_RUNNING);
    }
}

void handleDeviceClaiming() {
    if (!fsm.justEntered()) return;

    if (firestoreRepo == nullptr) {
        // Previously this state had no exit when the repo was null.
        Serial.println(F("[Claiming] firestoreRepo is null, skipping"));
    } else if (claimedUid.length() > 0) {
        Serial.print(F("[Claiming] Attempting claim for uid len="));
        Serial.println(claimedUid.length());
        if (firestoreRepo->claimDevice(claimedUid)) {
            Serial.println(F("[Claiming] Success"));
        } else {
            Serial.println(F("[Claiming] Failed, continuing anyway"));
        }
    } else {
        Serial.println(F("[Claiming] No UID, skipping"));
    }

    fsm.transition(DeviceState::CAPABILITY_DETECT);
}

void handleCapabilityDetect() {
    if (!fsm.justEntered()) return;

    // Probe the sensor once per boot - Bme680Driver::detect() allocates.
    static bool sensorProbed = false;
    if (!sensorProbed) {
        sensorProbed = true;
        bme680Detected = bme680.begin();
    }

    if (firestoreRepo != nullptr) {
        // Read current state from Firestore
        int dummy;
        String tzPosix;
        firestoreRepo->getDeviceDoc(dummy, bme680Present, tzPosix);
        applyTimeZone(tzPosix);

        // Update if changed
        if (bme680Detected != bme680Present) {
            firestoreRepo->updateDeviceCapability(bme680Detected);
            bme680Present = bme680Detected;
        }
    } else {
        bme680Present = bme680Detected;
    }

    Serial.print(F("[Capability] BME680: "));
    Serial.println(bme680Present ? "present" : "not present");

    fsm.transition(DeviceState::CONFIG_LOADING);
}

void handleConfigLoading() {
    // Runs once per entry into CONFIG_LOADING. The 60s config poll re-enters
    // this state whenever configVersion changes, so the guard must be tied to
    // state entry - a permanent `static bool` would make every reload after the
    // first a no-op and strand the device here forever.
    if (!fsm.justEntered()) return;

    if (firestoreRepo == nullptr) {
        Serial.println(F("[Config] firestoreRepo is null, skipping"));
        // Still transition to RUNNING even without config
        fsm.transition(DeviceState::RUNNING);
        return;
    }

    {
        // Read config version
        int configVersion;
        String tzPosix;
        if (firestoreRepo->checkConfigVersion(configVersion, tzPosix)) {
            // Outside the version guard: a timezone change is applied even when
            // configVersion happens to be unchanged, and costs nothing since the
            // doc was fetched either way.
            applyTimeZone(tzPosix);
            if (configVersion != currentConfigVersion) {
                Serial.print(F("[Config] Loading config version: "));
                Serial.println(configVersion);

                std::vector<ScreenConfig> screens;
                if (firestoreRepo->getScreens(screens)) {
                    Serial.print(F("[Config] Firestore returned "));
                    Serial.print(screens.size());
                    Serial.println(F(" screens"));
                    for (size_t i = 0; i < screens.size(); i++) {
                        ScreenConfig& sc = screens[i];
                        Serial.print(F("[Config] Screen["));
                        Serial.print(i);
                        Serial.print(F("] id="));
                        Serial.print(sc.id);
                        Serial.print(F(" type="));
                        Serial.print(sc.type);
                        Serial.print(F(" order="));
                        Serial.print(sc.order);
                        Serial.print(F(" enabled="));
                        Serial.print(sc.enabled ? 1 : 0);
                        Serial.print(F(" durationMs="));
                        Serial.print(sc.durationMs);
                        Serial.print(F(" assetId="));
                        Serial.print(sc.assetId.length() > 0 ? sc.assetId.c_str() : "(empty)");
                        Serial.print(F(" pairId="));
                        Serial.print(sc.pairId.length() > 0 ? sc.pairId.c_str() : "(empty)");
                        Serial.print(F(" sharedScreenId="));
                        Serial.print(sc.sharedScreenId.length() > 0 ? sc.sharedScreenId.c_str() : "(empty)");
                        Serial.print(F(" poolSize="));
                        Serial.print(sc.availableAssetIds.size());
                        Serial.print(F(" defaultAssetId="));
                        Serial.println(sc.defaultAssetId.length() > 0 ? sc.defaultAssetId.c_str() : "(empty)");
                        // The screen document owns its asset pool. Only fall back
                        // to the pair's shared document when the screen carries
                        // no pool of its own.
                        if (sc.availableAssetIds.empty() && sc.pairId.length() > 0 && sc.sharedScreenId.length() > 0) {
                            SharedScreenConfig sharedConfig;
                            if (firestoreRepo->getSharedScreen(sc.pairId, sc.sharedScreenId, sharedConfig)) {
                                sc.defaultAssetId = sharedConfig.defaultAssetId;
                                sc.availableAssetIds = sharedConfig.availableAssetIds;
                                sc.allowManualSwitch = sharedConfig.allowManualSwitch;
                            }
                        }
                        // Start on the default asset, not blindly on the first
                        // entry of the pool.
                        sc.currentAssetIndex = 0;
                        if (sc.defaultAssetId.length() > 0) {
                            sc.assetId = sc.defaultAssetId;
                            for (size_t a = 0; a < sc.availableAssetIds.size(); a++) {
                                if (sc.availableAssetIds[a] == sc.defaultAssetId) {
                                    sc.currentAssetIndex = (int)a;
                                    break;
                                }
                            }
                        } else if (sc.assetId.length() == 0 && !sc.availableAssetIds.empty()) {
                            sc.assetId = sc.availableAssetIds[0];
                        }
                        // Normalize type for comparison
                        String scTypeUpper = sc.type;
                        scTypeUpper.toUpperCase();
                        // A pool with no default must still be cached, so this
                        // cannot gate on assetId alone.
                        if ((scTypeUpper == "IMAGE" || scTypeUpper == "ANIMATION") &&
                            (sc.assetId.length() > 0 || !sc.availableAssetIds.empty())) {
                            Serial.print(F("[Config] Loading asset for screen["));
                            Serial.print(i);
                            Serial.print(F("]: "));
                            Serial.println(sc.assetId);
                            AssetData assetData;
                            if (firestoreRepo->getAsset(sc.assetId, assetData) && assetData.pixelsJson.length() > 0) {
                                Serial.print(F("[Config] Asset loaded, parsing... pixelsJsonLen="));
                                Serial.println(assetData.pixelsJson.length());
                                CachedAsset cached;
                                if (assetCache.parseAsset(sc.assetId, assetData.pixelsJson, cached)) {
                                    assetCache.addAsset(cached);
                                    Serial.println(F("[Config] Asset cached successfully"));
                                } else {
                                    Serial.println(F("[Config] Asset parse failed"));
                                }
                            } else {
                                Serial.print(F("[Config] Asset load failed or empty: pixelsJsonLen="));
                                Serial.println(assetData.pixelsJson.length());
                            }
                            for (size_t a = 0; a < sc.availableAssetIds.size(); a++) {
                                const String& aid = sc.availableAssetIds[a];
                                if (aid.length() > 0 && assetCache.getAsset(aid) == nullptr) {
                                    AssetData ad;
                                    if (firestoreRepo->getAsset(aid, ad) && ad.pixelsJson.length() > 0) {
                                        CachedAsset c;
                                        if (assetCache.parseAsset(aid, ad.pixelsJson, c)) {
                                            assetCache.addAsset(c);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    playlist.setScreens(screens);
                    // Only mark this version as consumed once it actually loaded.
                    // Leaving it unchanged on failure lets the next poll retry
                    // instead of silently dropping the update.
                    currentConfigVersion = configVersion;
                    } else {
                        Serial.println(F("[Config] getScreens() returned false, keeping cached playlist"));
                    }
            } else {
                Serial.print(F("[Config] Config version unchanged: "));
                Serial.println(configVersion);
            }
        } else {
            Serial.println(F("[Config] Failed to check config version"));
        }
        
        // Initialize button actions
        if (buttonActions == nullptr) {
            buttonActions = new ButtonActions(&buttons, &playlist, &matrix, &nvs, rtdbRepo);
        }
        
        // Schedule periodic tasks. Once per boot - re-registering on every
        // config reload would reset each task's interval timer.
        static bool tasksScheduled = false;
        if (!tasksScheduled) {
            tasksScheduled = true;
            scheduler.schedulePresenceUpdate(updatePresence);
            if (bme680Present) {
                scheduler.scheduleTelemetryUpdate(updateTelemetry);
            }
            scheduler.scheduleConfigPoll(checkConfigVersion);
            scheduler.scheduleNtpSync(syncTime);
        }

        Serial.println(F("[Config] Transitioning to RUNNING"));
        fsm.transition(DeviceState::RUNNING);
    }
}

void handleRunning() {
    // Update sensor readings
    if (bme680Present && millis() - lastSensorReadMs > 2000) {
        bme680.read(sensorTemp, sensorHumidity, sensorPressure, sensorGas);
        lastSensorReadMs = millis();
    }
    
    // Auto-rotate the playlist. Manual navigation (the buttons) resets the
    // timer via next()/previous(), so a button press postpones the next
    // automatic change rather than fighting it.
    // Compiled out when SCREEN_AUTO_ROTATE is 0: screens then change only on
    // a PREV/NEXT button press.
#if SCREEN_AUTO_ROTATE
    if (playlist.shouldRotate()) {
        playlist.next();
    }
#endif
    
    // Render current screen
    ScreenConfig* screen = playlist.getCurrentScreen();
    static int lastLoggedIndex = -999;
    static unsigned long lastRenderLogMs = 0;
    int curIndex = playlist.getCurrentIndex();
    bool logRender = (millis() - lastRenderLogMs >= 5000) || (screen != nullptr && lastLoggedIndex != curIndex);
    if (screen == nullptr) {
        if (lastLoggedIndex != -2) {
            Serial.println(F("[Render] No screen (playlist empty or null)"));
            lastLoggedIndex = -2;
        }
    } else if (logRender) {
        lastRenderLogMs = millis();
        lastLoggedIndex = curIndex;
        Serial.print(F("[Render] Screen index="));
        Serial.print(curIndex);
        Serial.print(F(" type="));
        Serial.print(screen->type);
        Serial.print(F(" durationMs="));
        Serial.print(screen->durationMs);
        Serial.print(F(" assetId="));
        Serial.println(playlist.getCurrentAssetId().length() > 0 ? playlist.getCurrentAssetId().c_str() : "(none)");
    }
    if (screen != nullptr) {
        // Normalize type to uppercase for comparison (in case Firestore returns lowercase)
        String typeUpper = screen->type;
        typeUpper.toUpperCase();
        if (typeUpper == "CLOCK") {
            // Render clock
            time_t now = time(nullptr);
            
            if (now < 1000000000) {
                if (logRender) Serial.println(F("[Render] Branch: CLOCK (invalid time -> red)"));
                // Invalid time - show test pattern
                matrix.fill(matrix.color(255, 0, 0)); // Red = time invalid
                matrix.show();
            } else {
                if (logRender) Serial.println(F("[Render] Branch: CLOCK"));
                
                // Parse config JSON to get clock settings
                bool showSeconds = true; // Default
                uint32_t backgroundColor = 0x000000; // Black
                uint32_t digitColor = 0xFFFFFF; // White
                uint32_t colonColor = 0x00FFFF; // Cyan
                String format = "24H"; // Default
                String layout = "HHMM_PLUS_SECONDS_BAR"; // Default
                bool blinkColon = false; // Default

                if (screen->configJson.length() > 0) {
                    DynamicJsonDocument configDoc(2048);
                    if (deserializeJson(configDoc, screen->configJson) == DeserializationError::Ok) {
                        if (configDoc.containsKey("showSeconds")) {
                            showSeconds = configDoc["showSeconds"].as<bool>();
                        }
                        if (configDoc.containsKey("backgroundColor")) {
                            backgroundColor = configDoc["backgroundColor"].as<uint32_t>();
                        }
                        if (configDoc.containsKey("digitColor")) {
                            digitColor = configDoc["digitColor"].as<uint32_t>();
                        }
                        if (configDoc.containsKey("colonColor")) {
                            colonColor = configDoc["colonColor"].as<uint32_t>();
                        }
                        if (configDoc.containsKey("format")) {
                            format = configDoc["format"].as<String>();
                        }
                        if (configDoc.containsKey("blinkColon")) {
                            blinkColon = configDoc["blinkColon"].as<bool>();
                        }
                        // layout is still derived from showSeconds below rather
                        // than read from config.
                    }
                }
                
                // Choose layout based on showSeconds
                if (!showSeconds) {
                    layout = "BIG_HHMM"; // No seconds bar
                }
                
                // Argument order matters here: this call used to pass
                // (..., false, showSeconds), which put showSeconds into
                // blinkColon and made the colon blink whenever seconds were on.
                renderClock.render(format, layout,
                                  digitColor, colonColor, backgroundColor,
                                  showSeconds, blinkColon);
            }
        } else if (typeUpper == "SENSOR" && bme680Present) {
            if (logRender) Serial.println(F("[Render] Branch: SENSOR"));

            // Defaults, overridden by the screen's config document.
            bool showTemperature = true;
            bool showHumidity = true;
            bool showPressure = false;
            String units = "METRIC";
            uint32_t numberColor = 0xFF8800;
            uint32_t accentColor = 0xFFFFFF;
            uint32_t backgroundColor = 0x000000;

            if (screen->configJson.length() > 0) {
                DynamicJsonDocument configDoc(1024);
                if (deserializeJson(configDoc, screen->configJson) == DeserializationError::Ok) {
                    if (configDoc.containsKey("showTemperature")) showTemperature = configDoc["showTemperature"].as<bool>();
                    if (configDoc.containsKey("showHumidity")) showHumidity = configDoc["showHumidity"].as<bool>();
                    if (configDoc.containsKey("showPressure")) showPressure = configDoc["showPressure"].as<bool>();
                    if (configDoc.containsKey("useMetricUnits")) units = configDoc["useMetricUnits"].as<bool>() ? "METRIC" : "IMPERIAL";
                    if (configDoc.containsKey("numberColor")) numberColor = configDoc["numberColor"].as<uint32_t>();
                    if (configDoc.containsKey("accentColor")) accentColor = configDoc["accentColor"].as<uint32_t>();
                    if (configDoc.containsKey("backgroundColor")) backgroundColor = configDoc["backgroundColor"].as<uint32_t>();
                }
            }

            std::vector<String> metrics;
            if (showTemperature) metrics.push_back("temperature");
            if (showHumidity) metrics.push_back("humidity");
            if (showPressure) metrics.push_back("pressure");
            if (metrics.empty()) metrics.push_back("temperature"); // Never render an empty screen

            // AUTO_CYCLE: advance the metric on a timer. sensorMetricIndex was
            // previously passed in but never incremented, pinning the display
            // to the first metric forever.
            static unsigned long lastMetricSwitchMs = 0;
            if (millis() - lastMetricSwitchMs >= SENSOR_CYCLE_MS) {
                lastMetricSwitchMs = millis();
                sensorMetricIndex++;
            }

            renderSensor.render("AUTO_CYCLE", "BIG_VALUE_WITH_LABEL",
                               metrics, units,
                               numberColor, accentColor, backgroundColor,
                               sensorTemp, sensorHumidity, sensorPressure, sensorGas,
                               sensorMetricIndex);
        } else if (typeUpper == "IMAGE" || typeUpper == "ANIMATION") {
            String assetId = playlist.getCurrentAssetId();
            CachedAsset* asset = assetId.length() > 0 ? assetCache.getAsset(assetId) : nullptr;
            // Only try to load asset if not cached and not recently failed
            static String lastFailedAssetId = "";
            static unsigned long lastAssetLoadAttemptMs = 0;
            if (asset == nullptr && assetId.length() > 0 && firestoreRepo != nullptr) {
                // Don't retry too frequently (wait at least 10 seconds between attempts)
                if (assetId != lastFailedAssetId || (millis() - lastAssetLoadAttemptMs > 10000)) {
                    lastAssetLoadAttemptMs = millis();
                    AssetData assetData;
                    if (firestoreRepo->getAsset(assetId, assetData) && assetData.pixelsJson.length() > 0) {
                        CachedAsset cached;
                        if (assetCache.parseAsset(assetId, assetData.pixelsJson, cached)) {
                            assetCache.addAsset(cached);
                            asset = assetCache.getAsset(assetId);
                            lastFailedAssetId = ""; // Clear failure flag on success
                        } else {
                            lastFailedAssetId = assetId; // Remember failed asset
                        }
                    } else {
                        lastFailedAssetId = assetId; // Remember failed asset
                    }
                }
            }
            if (logRender) {
                Serial.print(F("[Render] Branch: "));
                Serial.print(screen->type);
                Serial.print(F(" asset="));
                Serial.println(asset != nullptr && asset->isValid() ? "ok" : "null/invalid");
            }
            if (typeUpper == "IMAGE") {
                renderAsset.renderImage(asset, 0x000000);
            } else {
                renderAsset.renderAnimation(asset, 0x000000);
            }
        } else {
            if (logRender) Serial.println(F("[Render] Branch: fallback (unknown type or SENSOR without BME)"));
            // Unknown type or SENSOR without BME680: show placeholder so display updates
            matrix.fill(matrix.color(32, 32, 32));
            matrix.show();
        }
    } else {
        // No screens - show default pattern
        matrix.fill(matrix.color(64, 64, 64));
        matrix.show();
    }
    // Always push buffer to matrix so last drawn frame is visible
    matrix.show();
}

void handleOfflineRunning() {
    // Similar to RUNNING but without Firebase operations
    handleRunning();
    
    // Try to reconnect periodically
    static unsigned long lastReconnectAttempt = 0;
    if (millis() - lastReconnectAttempt > 30000) { // Every 30 seconds
        if (WiFi.isConnected()) {
            Serial.println(F("[Offline] Attempting Firebase reconnect"));
            fsm.transition(DeviceState::FIREBASE_CONNECTING);
        }
        lastReconnectAttempt = millis();
    }
}

void handleErrorRecovery() {
    // Error recovery logic
    Serial.println(F("[Error] In recovery mode"));
    delay(5000);
    // Try to recover or restart
    ESP.restart();
}

// Periodic task callbacks
void updatePresence() {
    if (rtdbRepo == nullptr) {
        Serial.println(F("[Presence] rtdbRepo is null, skipping"));
        return;
    }
    if (!WiFi.isConnected()) {
        Serial.println(F("[Presence] Wi-Fi not connected, skipping"));
        return;
    }
    
    bool success = rtdbRepo->updatePresence(true);
    if (!success) {
        Serial.println(F("[Presence] Update failed"));
    }
}

void updateTelemetry() {
    if (rtdbRepo == nullptr) {
        Serial.println(F("[Telemetry] rtdbRepo is null, skipping"));
        return;
    }
    if (!bme680Present) {
        Serial.println(F("[Telemetry] BME680 not present, skipping"));
        return;
    }
    if (!WiFi.isConnected()) {
        Serial.println(F("[Telemetry] Wi-Fi not connected, skipping"));
        return;
    }
    
    bool success = rtdbRepo->pushTelemetry(sensorTemp, sensorHumidity, sensorPressure, sensorGas);
    if (!success) {
        Serial.println(F("[Telemetry] Push failed"));
    }
}

void checkConfigVersion() {
    // Only request a reload from a state that can actually service one.
    // Re-entering CONFIG_LOADING from CONFIG_LOADING is not a state change, so
    // it would not raise the entry latch and the device would never leave.
    DeviceState state = fsm.getState();
    if (state != DeviceState::RUNNING && state != DeviceState::OFFLINE_RUNNING) return;

    if (firestoreRepo != nullptr && WiFi.isConnected()) {
        int version;
        String tzPosix;
        if (firestoreRepo->checkConfigVersion(version, tzPosix)) {
            // This is the 60s poll, so it is what actually picks up a timezone
            // the owner changed in the app. Applied before the version guard:
            // the doc has already been fetched, and a zone change should land
            // even if the screen config itself is untouched.
            applyTimeZone(tzPosix);
            if (version != currentConfigVersion) {
                Serial.println(F("[Config] Version changed, reloading"));
                fsm.transition(DeviceState::CONFIG_LOADING);
            }
        }
    }
}

void syncTime() {
    if (WiFi.isConnected() && timeSync.shouldSync()) {
        timeSync.sync(firebaseClient.getApp());
    }
}
