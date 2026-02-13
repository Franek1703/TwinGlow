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
        
        Serial.println(F("[BLE] Provisioning complete, saving credentials"));
        
        bleStarted = false;
        
        // Transition to Wi-Fi connecting
        fsm.transition(DeviceState::WIFI_CONNECTING);
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

void handleTimeSync() {
    static bool syncAttempted = false;
    static unsigned long syncStartMs = 0;
    
    if (!syncAttempted) {
        syncStartMs = millis();
        if (timeSync.sync(firebaseClient.getApp())) {
            // Verify time is valid before proceeding
            delay(100); // Small delay to let time() update
            time_t now = time(nullptr);
            if (now >= 1000000000) {
                Serial.print(F("[TimeSync] Success, time verified: epoch="));
                Serial.println(now);
                syncAttempted = true;
                fsm.transition(DeviceState::FIREBASE_CONNECTING);
            } else {
                Serial.println(F("[TimeSync] Sync reported success but time invalid, waiting..."));
                // Will retry on next loop
            }
        } else {
            // Wait a bit and check if time becomes valid (NTP might still be syncing)
            if (millis() - syncStartMs > 3000) {
                delay(100);
                time_t now = time(nullptr);
                if (now >= 1000000000) {
                    Serial.print(F("[TimeSync] Time became valid after wait: epoch="));
                    Serial.println(now);
                    syncAttempted = true;
                    fsm.transition(DeviceState::FIREBASE_CONNECTING);
                } else {
                    Serial.println(F("[TimeSync] Failed, continuing anyway (time may sync later)"));
                    syncAttempted = true;
                    fsm.transition(DeviceState::FIREBASE_CONNECTING);
                }
            }
        }
    }
}

void handleFirebaseConnecting() {
    static bool firebaseStarted = false;
    
    if (!firebaseStarted) {
        if (firebaseClient.begin()) {
            firestoreRepo = new FirestoreRepo(
                &firebaseClient,
                FIREBASE_PROJECT_ID,
                deviceId
            );
            rtdbRepo = new RtdbRepo(
                &firebaseClient,
                deviceId
            );
            firebaseStarted = true;
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
}

void handleDeviceClaiming() {
    static bool claimingAttempted = false;
    
    if (!claimingAttempted && firestoreRepo != nullptr) {
        if (claimedUid.length() > 0) {
            Serial.print(F("[Claiming] Attempting claim for uid len="));
            Serial.println(claimedUid.length());
            if (firestoreRepo->claimDevice(claimedUid)) {
                claimingAttempted = true;
                Serial.println(F("[Claiming] Success"));
                fsm.transition(DeviceState::CAPABILITY_DETECT);
            } else {
                Serial.println(F("[Claiming] Failed, continuing anyway"));
                claimingAttempted = true;
                fsm.transition(DeviceState::CAPABILITY_DETECT);
            }
        } else {
            Serial.println(F("[Claiming] No UID, skipping"));
            claimingAttempted = true;
            fsm.transition(DeviceState::CAPABILITY_DETECT);
        }
    }
}

void handleCapabilityDetect() {
    static bool detectAttempted = false;
    
    if (!detectAttempted) {
        // Try to detect BME680
        bme680Detected = bme680.begin();
        
        if (firestoreRepo != nullptr) {
            // Read current state from Firestore
            int dummy;
            firestoreRepo->getDeviceDoc(dummy, bme680Present);
            
            // Update if changed
            if (bme680Detected != bme680Present) {
                firestoreRepo->updateDeviceCapability(bme680Detected);
                bme680Present = bme680Detected;
            }
        } else {
            bme680Present = bme680Detected;
        }
        
        detectAttempted = true;
        Serial.print(F("[Capability] BME680: "));
        Serial.println(bme680Present ? "present" : "not present");
        
        fsm.transition(DeviceState::CONFIG_LOADING);
    }
}

void handleConfigLoading() {
    static bool loadingStarted = false;
    
    if (!loadingStarted) {
        if (firestoreRepo == nullptr) {
            Serial.println(F("[Config] firestoreRepo is null, skipping"));
            // Still transition to RUNNING even without config
            loadingStarted = true;
            fsm.transition(DeviceState::RUNNING);
            return;
        }
        
        loadingStarted = true;
        
        // Read config version
        int configVersion;
        if (firestoreRepo->checkConfigVersion(configVersion)) {
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
                        Serial.println(sc.sharedScreenId.length() > 0 ? sc.sharedScreenId.c_str() : "(empty)");
                        if (sc.pairId.length() > 0 && sc.sharedScreenId.length() > 0) {
                            SharedScreenConfig sharedConfig;
                            if (firestoreRepo->getSharedScreen(sc.pairId, sc.sharedScreenId, sharedConfig)) {
                                sc.assetId = sharedConfig.defaultAssetId;
                                sc.availableAssetIds = sharedConfig.availableAssetIds;
                                sc.currentAssetIndex = 0;
                            }
                        }
                        // Normalize type for comparison
                        String scTypeUpper = sc.type;
                        scTypeUpper.toUpperCase();
                        if ((scTypeUpper == "IMAGE" || scTypeUpper == "ANIMATION") && sc.assetId.length() > 0) {
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
                    } else {
                        Serial.println(F("[Config] getScreens() returned false"));
                    }
                currentConfigVersion = configVersion;
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
        
        // Schedule periodic tasks
        scheduler.schedulePresenceUpdate(updatePresence);
        if (bme680Present) {
            scheduler.scheduleTelemetryUpdate(updateTelemetry);
        }
        scheduler.scheduleConfigPoll(checkConfigVersion);
        scheduler.scheduleNtpSync(syncTime);
        
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
    
    // Screen rotation disabled - only manual button switching
    // if (playlist.shouldRotate()) {
    //     playlist.next();
    // }
    
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
                        // Note: format and layout could also come from config if needed
                    }
                }
                
                // Choose layout based on showSeconds
                if (!showSeconds) {
                    layout = "BIG_HHMM"; // No seconds bar
                }
                
                renderClock.render(format, layout, 
                                  digitColor, colonColor, backgroundColor,
                                  false, showSeconds);
            }
        } else if (typeUpper == "SENSOR" && bme680Present) {
            if (logRender) Serial.println(F("[Render] Branch: SENSOR"));
            // Render sensor
            std::vector<String> metrics = {"temperature", "humidity"};
            renderSensor.render("AUTO_CYCLE", "BIG_VALUE_WITH_LABEL",
                               metrics, "METRIC",
                               0xFF8800, 0xFFFFFF, 0x000000,
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
    if (firestoreRepo != nullptr && WiFi.isConnected()) {
        int version;
        if (firestoreRepo->checkConfigVersion(version)) {
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
