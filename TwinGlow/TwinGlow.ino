/*
 * TwinGlow ESP32 Firmware
 * Complete firmware for 16x16 NeoPixel matrix device
 * 
 * See Config.h for configuration checklist and troubleshooting
 */

#include "Config.h"
#include "NvsStore.h"
#include "StateMachine.h"
#include "Scheduler.h"
#include "BleProvisioning.h"
#include "WifiManager.h"
#include "FirebaseClientWrap.h"
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
    
    Serial.println("\n\n=== TwinGlow Firmware Starting ===");
    Serial.print("FW Version: ");
    Serial.println(FW_VERSION);
    
    // Initialize state machine
    fsm.setState(DeviceState::BOOT);
    
    // Initialize matrix for visual feedback
    if (!matrix.begin()) {
        Serial.println("[ERROR] Matrix initialization failed");
    }
    matrix.fill(matrix.color(0, 0, 255)); // Blue during boot
    matrix.show();
    
    // Initialize NVS
    if (!nvs.begin()) {
        Serial.println("[ERROR] NVS initialization failed");
        fsm.setError("NVS init failed");
        return;
    }
    
    fsm.transition(DeviceState::LOAD_NVS);
    
    // Load device ID
    if (!nvs.getDeviceId(deviceId)) {
        Serial.println("[ERROR] Failed to get device ID");
        return;
    }
    Serial.print("[NVS] Device ID: ");
    Serial.println(deviceId);
    
    // Load brightness
    uint8_t brightness = nvs.getBrightness();
    matrix.setBrightness(brightness);
    
    // Check provisioning status
    if (!nvs.isProvisioned()) {
        Serial.println("[NVS] Not provisioned, entering BLE mode");
        fsm.transition(DeviceState::PROVISIONING_BLE);
    } else {
        // Load Wi-Fi credentials
        String ssid, pass;
        if (nvs.getWifiSsid(ssid)) {
            nvs.getWifiPass(pass);
            Serial.print("[NVS] Wi-Fi SSID: ");
            Serial.println(ssid);
            fsm.transition(DeviceState::WIFI_CONNECTING);
        } else {
            Serial.println("[NVS] No Wi-Fi credentials, entering BLE mode");
            fsm.transition(DeviceState::PROVISIONING_BLE);
        }
    }
    
    // Load claimed UID
    nvs.getClaimedUid(claimedUid);
    
    // Initialize buttons
    buttons.begin();
    
    Serial.println("[Setup] Complete");
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
            Serial.println("[BLE] Failed to start");
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
        
        Serial.println("[BLE] Provisioning complete, saving credentials");
        
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
                matrix.fill(matrix.color(0, 255, 0)); // Green during Wi-Fi
                matrix.show();
            }
        } else {
            Serial.println("[WiFi] No credentials, entering BLE mode");
            fsm.transition(DeviceState::PROVISIONING_BLE);
            return;
        }
    }
    
    wifiManager.update();
    
    if (wifiManager.isConnected()) {
        Serial.println("[WiFi] Connected!");
        wifiStarted = false;
        fsm.transition(DeviceState::TIME_SYNC);
    } else if (wifiManager.shouldEnterProvisioning()) {
        Serial.println("[WiFi] Too many failures, entering BLE mode");
        wifiManager.reset();
        wifiStarted = false;
        fsm.transition(DeviceState::PROVISIONING_BLE);
    }
}

void handleTimeSync() {
    static bool syncAttempted = false;
    
    if (!syncAttempted) {
        if (timeSync.sync(firebaseClient.getApp())) {
            syncAttempted = true;
            fsm.transition(DeviceState::FIREBASE_CONNECTING);
        } else {
            Serial.println("[TimeSync] Failed, continuing anyway");
            syncAttempted = true;
            // Continue even if sync fails
            fsm.transition(DeviceState::FIREBASE_CONNECTING);
        }
    }
}

void handleFirebaseConnecting() {
    static bool firebaseStarted = false;
    
    if (!firebaseStarted) {
        if (firebaseClient.begin()) {
            firestoreRepo = new FirestoreRepo(
                firebaseClient.getFirestore(),
                FIREBASE_PROJECT_ID,
                deviceId
            );
            rtdbRepo = new RtdbRepo(
                firebaseClient.getRtdb(),
                deviceId
            );
            firebaseStarted = true;
            Serial.println("[Firebase] Connected");
            fsm.transition(DeviceState::DEVICE_CLAIMING);
        } else {
            Serial.println("[Firebase] Connection failed");
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
            if (firestoreRepo->claimDevice(claimedUid)) {
                claimingAttempted = true;
                fsm.transition(DeviceState::CAPABILITY_DETECT);
            } else {
                Serial.println("[Claiming] Failed, continuing anyway");
                claimingAttempted = true;
                fsm.transition(DeviceState::CAPABILITY_DETECT);
            }
        } else {
            Serial.println("[Claiming] No UID, skipping");
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
        Serial.print("[Capability] BME680: ");
        Serial.println(bme680Present ? "present" : "not present");
        
        fsm.transition(DeviceState::CONFIG_LOADING);
    }
}

void handleConfigLoading() {
    static bool loadingStarted = false;
    
    if (!loadingStarted && firestoreRepo != nullptr) {
        loadingStarted = true;
        
        // Read config version
        int configVersion;
        if (firestoreRepo->checkConfigVersion(configVersion)) {
            if (configVersion != currentConfigVersion) {
                Serial.print("[Config] Loading config version: ");
                Serial.println(configVersion);
                
                // TODO: Load screens, shared screens, assets
                // For now, create empty playlist
                std::vector<ScreenConfig> screens;
                playlist.setScreens(screens);
                
                currentConfigVersion = configVersion;
            }
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
        
        fsm.transition(DeviceState::RUNNING);
    }
}

void handleRunning() {
    // Update sensor readings
    if (bme680Present && millis() - lastSensorReadMs > 2000) {
        bme680.read(sensorTemp, sensorHumidity, sensorPressure, sensorGas);
        lastSensorReadMs = millis();
    }
    
    // Check screen rotation
    if (playlist.shouldRotate()) {
        playlist.next();
    }
    
    // Render current screen
    ScreenConfig* screen = playlist.getCurrentScreen();
    if (screen != nullptr) {
        if (screen->type == "CLOCK") {
            // Render clock
            renderClock.render("24H", "HHMM_PLUS_SECONDS_BAR", 
                              0xFFFFFF, 0x00FFFF, 0x000000,
                              false, true);
        } else if (screen->type == "SENSOR" && bme680Present) {
            // Render sensor
            std::vector<String> metrics = {"temperature", "humidity"};
            renderSensor.render("AUTO_CYCLE", "BIG_VALUE_WITH_LABEL",
                               metrics, "METRIC",
                               0xFF8800, 0xFFFFFF, 0x000000,
                               sensorTemp, sensorHumidity, sensorPressure, sensorGas,
                               sensorMetricIndex);
        } else if (screen->type == "IMAGE" || screen->type == "ANIMATION") {
            // Render asset
            // TODO: Get current asset from screen
            CachedAsset* asset = nullptr;
            if (screen->type == "IMAGE") {
                renderAsset.renderImage(asset, 0x000000);
            } else {
                renderAsset.renderAnimation(asset, 0x000000);
            }
        }
    } else {
        // No screens - show default pattern
        matrix.fill(matrix.color(64, 64, 64));
        matrix.show();
    }
}

void handleOfflineRunning() {
    // Similar to RUNNING but without Firebase operations
    handleRunning();
    
    // Try to reconnect periodically
    static unsigned long lastReconnectAttempt = 0;
    if (millis() - lastReconnectAttempt > 30000) { // Every 30 seconds
        if (WiFi.isConnected()) {
            Serial.println("[Offline] Attempting Firebase reconnect");
            fsm.transition(DeviceState::FIREBASE_CONNECTING);
        }
        lastReconnectAttempt = millis();
    }
}

void handleErrorRecovery() {
    // Error recovery logic
    Serial.println("[Error] In recovery mode");
    delay(5000);
    // Try to recover or restart
    ESP.restart();
}

// Periodic task callbacks
void updatePresence() {
    if (rtdbRepo != nullptr && WiFi.isConnected()) {
        rtdbRepo->updatePresence(true);
    }
}

void updateTelemetry() {
    if (rtdbRepo != nullptr && bme680Present && WiFi.isConnected()) {
        rtdbRepo->pushTelemetry(sensorTemp, sensorHumidity, sensorPressure, sensorGas);
    }
}

void checkConfigVersion() {
    if (firestoreRepo != nullptr && WiFi.isConnected()) {
        int version;
        if (firestoreRepo->checkConfigVersion(version)) {
            if (version != currentConfigVersion) {
                Serial.println("[Config] Version changed, reloading");
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
