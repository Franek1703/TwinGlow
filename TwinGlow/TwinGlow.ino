/*
 * TwinGlow ESP32 Firmware
 * Complete firmware for 16x16 NeoPixel matrix device
 * 
 * See Config.h for configuration checklist and troubleshooting
 */

// Let FirebaseClient use external PSRAM (define before any Firebase include)
#define ENABLE_PSRAM

#include "PairingConfig.h"
#include "SleepSchedule.h"
#include "NvsStore.h"
#include "StateMachine.h"
#include "Scheduler.h"
#include "BleProvisioning.h"
#include "WifiManager.h"
#include "FirebaseClientWrap.h"
#include "CloudWorker.h"
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
#include "PairingController.h"
#include "PlaylistUpdate.h"

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
CloudWorker cloudWorker;
FirestoreRepo* firestoreRepo = nullptr;
RtdbRepo* rtdbRepo = nullptr;
TimeSync timeSync;
MatrixDriver matrix;
RenderClock renderClock(&matrix);
RenderSensor renderSensor(&matrix);
RenderAsset renderAsset(&matrix);
RenderAsset receivedRenderer(&matrix);
PairingController pairing(&nvs, &cloudWorker, &receivedRenderer);
AssetCache assetCache;
ScreenPlaylist playlist;
Buttons buttons;
ButtonActions* buttonActions = nullptr;
Bme680Driver bme680;

// State variables
String deviceId;
String claimedUid;
int currentConfigVersion = -1;
String currentSharingPairId;
int currentSharingVersion=-1;
bool currentSharingActive=false, stagingValidated=false;
// Last value seen on the RTDB doorbell (/config/{deviceId}/configVersion).
// -1 means "not read yet"; the first successful read only records the value,
// since boot has just loaded the config and a reload there would be redundant.
int lastSeenRevision = -1;
bool bme680Present = false;
bool bme680Detected = false;
// Last brightness applied *from the device doc*. -1 means the doc has not been
// read yet. Kept separate from the live matrix value so a +/- button press is
// not reverted by the next poll re-asserting an unchanged cloud value.
int lastCloudBrightness = -1;
// Sleep window, loaded from NVS at boot and refreshed from the device doc.
SleepSettings sleepSettings;
bool sleepActive = false;
unsigned long lastSleepCheckMs = 0;
float sensorTemp = 0, sensorHumidity = 0, sensorPressure = 0, sensorGas = 0;
int sensorMetricIndex = 0;
unsigned long lastSensorReadMs = 0;
std::unique_ptr<PlaylistUpdate> playlistUpdate;
bool screensFetchPending=false;
String stagedAssetInFlight;
String pendingRuntimeAssetId;
String lastFailedRuntimeAssetId;
unsigned long lastRuntimeAssetAttemptMs = 0;

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
        matrix.fillStatus(matrix.color(0, 255, 255)); // Dim cyan during boot
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

    // Load the cached sleep window for the same reason as the timezone below:
    // a boot that never reaches Firestore must still dim on schedule.
    nvs.getSleepSettings(sleepSettings);

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
    // Until the worker starts, boot owns token processing.
    if (firebaseClient.isInitialized() && !cloudWorker.isStarted()) firebaseClient.loop();
    // Update buttons
    buttons.update();
    
    // Handle button actions if initialized
    if (buttonActions != nullptr) {
        buttonActions->update();
    }

    // Consume background Firebase results without ever waiting for the worker.
    // A changed config is reloaded only after the worker has left its current
    // repository call, so the shared FirebaseClient is never used concurrently.
    processCloudResults();
    // Releases the brightness write-back once the buttons have stopped moving.
    cloudWorker.tick();
    // The worker asks, this task acts. Issuing WiFi.begin()/reconnect() from
    // the worker's core raced WifiManager's own retry and left the station
    // cycling through AUTH_EXPIRE, so the radio has exactly one owner.
    if (cloudWorker.consumeWifiCycleRequest()) {
        wifiManager.requestReconnect();
    }
    servicePlaylistUpdate();
    
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
            matrix.fillStatus(matrix.color(255, 255, 0)); // Yellow during provisioning
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

        matrix.fillStatus(matrix.color(0, 255, 0)); // Green: provisioned
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
                // matrix.fillStatus(matrix.color(0, 255, 0)); // Green during Wi-Fi
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
        // From this point onward a network outage is not a provisioning error.
        // Retry forever in the background while cached content keeps running.
        wifiManager.setPersistentReconnect(true);
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

// Applies the brightness and sleep window carried by the device doc.
//
// Brightness is deliberately applied only when the *document* value moves, not
// on every poll: the +/- buttons write straight to NVS, and re-asserting the
// cloud value every 60s would undo a button press within the minute. So the
// owner's slider wins when they move it, and the buttons own it in between.
void applyDeviceSettings(const DeviceDoc& doc) {
    if (doc.brightness >= 0) {
        uint8_t brightness = (uint8_t)constrain(doc.brightness, 0, 255);
        if ((int)brightness != lastCloudBrightness) {
            lastCloudBrightness = brightness;
            nvs.setBrightness(brightness);
            // While asleep the schedule owns the panel; the new value is stored
            // and takes effect at the end of the window.
            if (!sleepActive) {
                matrix.setBrightness(brightness);
            }
        }
    }

    if (doc.hasSleep) {
        if (doc.sleep.enabled != sleepSettings.enabled ||
            doc.sleep.startMinute != sleepSettings.startMinute ||
            doc.sleep.endMinute != sleepSettings.endMinute ||
            doc.sleep.brightness != sleepSettings.brightness) {
            sleepSettings = doc.sleep;
            nvs.setSleepSettings(sleepSettings);
            // Re-evaluate on the next pass rather than waiting out the interval,
            // so a schedule edit is visible straight away.
            lastSleepCheckMs = 0;
        }
    }
}

// Drops the panel to the sleep brightness inside the window and restores the
// owner's brightness outside it. A sleep brightness of 0 blanks the display,
// which setBrightness() cannot express - it clamps 0 up to 1.
//
// Returns true when the caller should skip rendering entirely.
bool updateSleepState() {
    unsigned long now = millis();
    if (lastSleepCheckMs != 0 && (now - lastSleepCheckMs) < SLEEP_CHECK_INTERVAL_MS) {
        return sleepActive && sleepSettings.brightness == 0;
    }
    lastSleepCheckMs = now;

    // An unsynced clock must never blank the panel: time(nullptr) returns a
    // pre-2001 epoch before the first NTP sync, and reading a window out of that
    // would dim the device for reasons the owner cannot see.
    bool shouldSleep = false;
    if (sleepSettings.enabled && TimeSync::isTimeValid()) {
        time_t nowEpoch = time(nullptr);
        struct tm tmNow;
        localtime_r(&nowEpoch, &tmNow);
        int nowMinute = tmNow.tm_hour * 60 + tmNow.tm_min;
        shouldSleep = isWithinSleepWindow(
            sleepSettings.startMinute, sleepSettings.endMinute, nowMinute);
    }

    if (shouldSleep != sleepActive) {
        sleepActive = shouldSleep;
        if (sleepActive) {
            Serial.print(F("[Sleep] Entering sleep window, brightness "));
            Serial.println(sleepSettings.brightness);
            if (sleepSettings.brightness > 0) {
                matrix.setBrightness(sleepSettings.brightness);
            }
        } else {
            Serial.println(F("[Sleep] Leaving sleep window"));
            matrix.setBrightness(nvs.getBrightness());
            // Nothing advanced while the panel was blank, so the frame timer is
            // stale. Restart at frame 0 instead of jumping on the first pass.
            renderAsset.resetAnimation();
            receivedRenderer.resetAnimation();
        }
    }
    // A settings edit can switch dim to blank without leaving the window.
    static bool wasBlank=false;
    bool dark=sleepActive && sleepSettings.brightness==0;
    if (dark && !wasBlank) {matrix.clear();matrix.show();}
    if (!dark && wasBlank) {renderAsset.resetAnimation();receivedRenderer.resetAnimation();}
    wasBlank=dark;
    return dark;
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

    // begin() is intentionally idempotent and does not touch the network on a
    // second call. Reset the real socket here or the old reconnect state merely
    // changes FSM labels while retaining the failed TLS session.
    if (firebaseClient.isInitialized()) {
        firebaseClient.resetTransport();
    }

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
        DeviceDoc deviceDoc;
        firestoreRepo->getDeviceDoc(deviceDoc);
        bme680Present = deviceDoc.bme680Present;
        applyTimeZone(deviceDoc.tzPosix);
        applyDeviceSettings(deviceDoc);

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

// Collects an asset id once. Screens routinely share assets - a pool entry is
// often another screen's default - and refetching the same document per screen
// would multiply the slowest part of a config reload.
static void addReferencedAsset(std::vector<String>& ids, const String& assetId) {
    if (assetId.length() == 0) return;
    for (const String& existing : ids) {
        if (existing == assetId) return;
    }
    ids.push_back(assetId);
}

void handleConfigLoading() {
    if (!fsm.justEntered()) return;
    if (!cloudWorker.isStarted() && firestoreRepo != nullptr) {
        cloudWorker.begin(&firebaseClient, firestoreRepo, rtdbRepo);
    }
    pairing.begin(deviceId);
    if (buttonActions == nullptr) {
        buttonActions = new ButtonActions(&buttons, &playlist, &matrix, &nvs,
                                         rtdbRepo, &cloudWorker, &pairing, &assetCache);
    }
    static bool scheduled=false;
    if (!scheduled) {
        scheduled=true;
        scheduler.schedulePresenceUpdate(updatePresence);
        if (bme680Present) scheduler.scheduleTelemetryUpdate(updateTelemetry);
        scheduler.scheduleConfigPoll(checkConfigVersion);
        scheduler.scheduleNtpSync(syncTime);
    }
    cloudWorker.requestConfigCheck();
    fsm.transition(DeviceState::RUNNING);
}

void servicePlaylistUpdate() {
    if (!playlistUpdate) return;
    if (playlistUpdate->ready()) {
        if(!stagingValidated) { cloudWorker.requestConfigCheck(); return; }
        playlistUpdate->cache.retainOnly(playlistUpdate->required);
        renderAsset.resetAnimation();
        playlist.setScreens(playlistUpdate->screens);
        assetCache=std::move(playlistUpdate->cache);
        currentConfigVersion=playlistUpdate->version;
        currentSharingPairId=playlistUpdate->sharingPairId;currentSharingVersion=playlistUpdate->sharingVersion;currentSharingActive=playlistUpdate->sharingActive;
        stagingValidated=false;
        playlistUpdate.reset();
        Serial.println(F("[Config] Staged playlist committed"));
    } else if (stagedAssetInFlight.isEmpty()) {
        String id = playlistUpdate->next();
        auto cached = playlistUpdate->cache.getAsset(id);
        if (cloudWorker.requestAsset(id, cached ? cached->sourceRevision : String())) {
            stagedAssetInFlight = id;
        }
    }
}

// Whether the CLOCK screen last rendered with a blinking colon. Read by
// frameIntervalFor() before the screen's config is parsed, and set by the CLOCK
// branch each time it paints - the first paint of a screen is always forced, so
// this is current from then on.
static bool clockColonBlinks = false;

// How long the panel may hold its current frame, by screen type. See the frame
// budget block in Config.h for why this exists.
static unsigned long frameIntervalFor(const ScreenConfig* screen) {
    if (screen == nullptr) return FRAME_INTERVAL_DEFAULT_MS;
    // strcasecmp, not the body's toUpperCase() or String::equalsIgnoreCase:
    // this runs on every pass and both of those allocate a String to do it.
    const char* type = screen->type.c_str();
    if (strcasecmp(type, "CLOCK") == 0) {
        return clockColonBlinks ? FRAME_INTERVAL_CLOCK_BLINK_MS
                                : FRAME_INTERVAL_CLOCK_MS;
    }
    if (strcasecmp(type, "SENSOR") == 0) return FRAME_INTERVAL_SENSOR_MS;
    if (strcasecmp(type, "ANIMATION") == 0) return FRAME_INTERVAL_ANIMATION_MS;
    if (strcasecmp(type, "IMAGE") == 0) return FRAME_INTERVAL_IMAGE_MS;
    return FRAME_INTERVAL_DEFAULT_MS;
}

void handleRunning() {
    // Runtime Wi-Fi maintenance is local/non-blocking and never paints status
    // colors. It was previously called only from WIFI_CONNECTING, leaving a
    // device that lost its AP permanently offline in RUNNING.
    wifiManager.update();

    // Dim or blank for the sleep window before anything is drawn. When the
    // window asks for a blank panel we return before the render body, not just
    // before show(): letting RenderAsset keep advancing frames behind a dark
    // panel would make an animation jump on wake.
    bool dark=updateSleepState();
    if (sleepActive && sleepSettings.brightness>0 && matrix.getBrightness()!=sleepSettings.brightness) matrix.setBrightness(sleepSettings.brightness);
    pairing.tick(dark);
    if (dark) return;
    if (pairing.hasOverride()) {
        static unsigned long lastReceivedFrame=0;
        if (millis()-lastReceivedFrame>=FRAME_INTERVAL_ANIMATION_MS) {
            lastReceivedFrame=millis();pairing.render();
        }
        return;
    }

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
    // Entering a screen restarts its animation rather than resuming whatever
    // frame it was on when the playlist last moved away.
    static int lastRenderedIndex = -1;
    bool screenChanged = (curIndex != lastRenderedIndex);
    if (screenChanged) {
        lastRenderedIndex = curIndex;
        renderAsset.resetAnimation();
    }

    // Frame budget. The body below ends in a show() on every path, and show()
    // holds interrupts off for ~7.6 ms across 256 WS2812s - running it once per
    // loop() pass repainted an unchanged clock about a hundred times a second.
    // A screen change paints at once; otherwise the panel waits for the budget
    // its content actually needs. Everything above this point (Wi-Fi, sensor
    // reads, playlist rotation) still runs every pass.
    static unsigned long lastFrameMs = 0;
    if (!screenChanged &&
        millis() - lastFrameMs < frameIntervalFor(screen)) {
        return;
    }
    lastFrameMs = millis();
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
                matrix.fillStatus(matrix.color(255, 0, 0)); // Red = time invalid
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
                    JsonDocument configDoc;
                    if (deserializeJson(configDoc, screen->configJson) == DeserializationError::Ok) {
                        if (!configDoc["showSeconds"].isNull()) {
                            showSeconds = configDoc["showSeconds"].as<bool>();
                        }
                        if (!configDoc["backgroundColor"].isNull()) {
                            backgroundColor = configDoc["backgroundColor"].as<uint32_t>();
                        }
                        if (!configDoc["digitColor"].isNull()) {
                            digitColor = configDoc["digitColor"].as<uint32_t>();
                        }
                        if (!configDoc["colonColor"].isNull()) {
                            colonColor = configDoc["colonColor"].as<uint32_t>();
                        }
                        if (!configDoc["format"].isNull()) {
                            format = configDoc["format"].as<String>();
                        }
                        if (!configDoc["blinkColon"].isNull()) {
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
                
                // Feeds frameIntervalFor(): a blinking colon needs four
                // frames a second, a still one needs a single frame a second.
                clockColonBlinks = blinkColon;

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
                JsonDocument configDoc;
                if (deserializeJson(configDoc, screen->configJson) == DeserializationError::Ok) {
                    if (!configDoc["showTemperature"].isNull()) showTemperature = configDoc["showTemperature"].as<bool>();
                    if (!configDoc["showHumidity"].isNull()) showHumidity = configDoc["showHumidity"].as<bool>();
                    if (!configDoc["showPressure"].isNull()) showPressure = configDoc["showPressure"].as<bool>();
                    if (!configDoc["useMetricUnits"].isNull()) units = configDoc["useMetricUnits"].as<bool>() ? "METRIC" : "IMPERIAL";
                    if (!configDoc["numberColor"].isNull()) numberColor = configDoc["numberColor"].as<uint32_t>();
                    if (!configDoc["accentColor"].isNull()) accentColor = configDoc["accentColor"].as<uint32_t>();
                    if (!configDoc["backgroundColor"].isNull()) backgroundColor = configDoc["backgroundColor"].as<uint32_t>();
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
            // A cache miss must not turn rendering into a network call. Queue
            // it for CloudWorker so a failed TLS handshake cannot freeze input.
            if (!playlistUpdate && asset == nullptr && assetId.length() > 0 && firestoreRepo != nullptr) {
                // Don't retry too frequently (wait at least 10 seconds between attempts)
                if (pendingRuntimeAssetId.length() == 0 &&
                    (assetId != lastFailedRuntimeAssetId ||
                     (millis() - lastRuntimeAssetAttemptMs > 10000))) {
                    lastRuntimeAssetAttemptMs = millis();
                    if (cloudWorker.requestAsset(assetId)) {
                        pendingRuntimeAssetId = assetId;
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
            // Unknown type or SENSOR without BME680: show placeholder so display updates.
            matrix.fillStatus(matrix.color(96, 96, 96));
            matrix.show();
        }
    } else {
        // No screens - show a dim grey status indicator.
        matrix.fillStatus(matrix.color(128, 128, 128));
        matrix.show();
    }
    // No trailing show() here: every branch above ends in one of its own, so
    // this was a second full strip write - and a second ~7.6 ms interrupt
    // blackout - for every frame.
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
    
    // The worker owns the blocking WiFiClientSecure call. enqueue() is
    // non-blocking and coalesces another presence tick while one is in flight.
    cloudWorker.requestPresence(true);
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
    
    cloudWorker.requestTelemetry(sensorTemp, sensorHumidity, sensorPressure, sensorGas);
}

void checkConfigVersion() {
    // Only request a reload from a state that can actually service one.
    // Re-entering CONFIG_LOADING from CONFIG_LOADING is not a state change, so
    // it would not raise the entry latch and the device would never leave.
    DeviceState state = fsm.getState();
    if (state != DeviceState::RUNNING && state != DeviceState::OFFLINE_RUNNING) return;

    if (firestoreRepo != nullptr && WiFi.isConnected()) {
        cloudWorker.requestConfigCheck();
    }
}

#if ENABLE_RTDB_DOORBELL
void checkConfigRevision() {
    // The doorbell only decides *when* to look; checkConfigVersion() still owns
    // the actual comparison and the CONFIG_LOADING transition, so the RTDB
    // counter never has to agree with Firestore's configVersion.
    DeviceState state = fsm.getState();
    if (state != DeviceState::RUNNING && state != DeviceState::OFFLINE_RUNNING) return;

    if (rtdbRepo == nullptr || !WiFi.isConnected()) return;

    cloudWorker.requestRevisionCheck();
}
#endif // ENABLE_RTDB_DOORBELL

void processCloudResults() {
    CloudResult result{};
    while (cloudWorker.popResult(result)) {
        bool wasOverride=pairing.hasOverride();
        pairing.process(result);
        if (wasOverride && !pairing.hasOverride()) playlist.resetRotationTimer();
        if (result.operation==CloudOperation::PAIR_STATE && result.success && result.pairState && result.pairState->revision != lastSeenRevision) {
            lastSeenRevision=result.pairState->revision;
            cloudWorker.requestConfigCheck();
        }
        switch (result.operation) {
            case CloudOperation::PRESENCE:
                // Logged on success too. A healthy presence tick and one that
                // was silently coalesced into a job that never completes used to
                // produce identical output - nothing at all - which made a
                // wedged worker indistinguishable from a working one.
                if (result.success) {
                    Serial.println(F("[Presence] Heartbeat ok"));
                } else {
                    Serial.println(F("[Presence] Background update failed"));
                }
                break;

            case CloudOperation::TELEMETRY:
                if (!result.success) Serial.println(F("[Telemetry] Background push failed"));
                break;

            case CloudOperation::CONFIG_CHECK:
                if (result.success && result.deviceDoc != nullptr) {
                    DeviceDoc& doc = *result.deviceDoc;
                    // Printed on every poll, not only when the version moves.
                    // An unchanged version was previously silent, so a device
                    // polling a different document than the app writes - the
                    // device id is random and is regenerated whenever NVS is
                    // erased - looked exactly like a device with nothing to do.
                    // The path makes that mismatch visible without a reboot.
                    Serial.print(F("[Config] Poll ok devices/"));
                    Serial.print(deviceId);
                    Serial.print(F(" remote="));
                    Serial.print(doc.configVersion);
                    Serial.print(F(" local="));
                    Serial.println(currentConfigVersion);
                    applyDeviceSettings(doc);
                    applyTimeZone(doc.tzPosix);
                    if((currentSharingActive && !doc.sharingActive) || (!currentSharingPairId.isEmpty() && doc.sharingPairId!=currentSharingPairId)) { playlist.removeSharedScreens(); renderAsset.resetAnimation(); }
                    if(playlistUpdate && playlistUpdate->ready()) {
                        stagingValidated = doc.configVersion==playlistUpdate->version && doc.sharingVersion==playlistUpdate->sharingVersion && doc.sharingPairId==playlistUpdate->sharingPairId && doc.sharingActive==playlistUpdate->sharingActive;
                        if(!stagingValidated)playlistUpdate.reset();
                    }
                    if (doc.configVersion != currentConfigVersion || doc.sharingVersion!=currentSharingVersion || doc.sharingPairId!=currentSharingPairId || doc.sharingActive!=currentSharingActive) {
                        if (!playlistUpdate && !screensFetchPending) {
                            screensFetchPending=cloudWorker.requestScreens(doc.configVersion);
                        }
                    }
                } else {
                    Serial.println(F("[Config] Background version check failed"));
                }
                break;

            case CloudOperation::REVISION_CHECK:
#if ENABLE_RTDB_DOORBELL
                if (result.success) {
                    if (lastSeenRevision == -1) {
                        lastSeenRevision = result.revision;
                    } else if (result.revision != lastSeenRevision) {
                        lastSeenRevision = result.revision;
                        Serial.print(F("[Config] RTDB revision changed to "));
                        Serial.print(result.revision);
                        Serial.println(F(", queueing Firestore check"));
                        cloudWorker.requestConfigCheck();
                    }
                }
#endif
                break;

            case CloudOperation::PAIR_EVENT:
                if (!result.success) Serial.println(F("[ButtonActions] Background pair event failed"));
                break;

            case CloudOperation::BRIGHTNESS_WRITE:
                if (result.success) {
                    // The document now holds what we just sent, so treat it as
                    // already applied: without this the next config check sees
                    // its own echo as a change and re-applies it.
                    lastCloudBrightness = result.brightness;
                    // The panel can have moved again while the write was in
                    // flight - a press landing after the worker read the value
                    // coalesces into the job already running. Re-queue so the
                    // document ends up on the value the owner stopped at.
                    uint8_t current = nvs.getBrightness();
                    if ((int)current != result.brightness) {
                        cloudWorker.requestBrightnessWrite(current);
                    }
                } else {
                    // Not retried here: NVS already holds the value, so the
                    // panel is right and only the app's slider is stale until
                    // the next local change. Retrying on the shared transport
                    // is what the worker's own backoff is for.
                    Serial.println(F("[ButtonActions] Brightness write-back failed"));
                }
                break;

            case CloudOperation::SCREENS_FETCH:
                screensFetchPending=false;
                if (result.success && result.screens) {
                    playlist.retainAuthorizedSharedScreens(*result.screens);
                    stagingValidated=false;
                    playlistUpdate.reset(new(std::nothrow)PlaylistUpdate(std::move(*result.screens),assetCache,result.revision));
                    if(playlistUpdate && result.deviceDoc) { playlistUpdate->sharingPairId=result.deviceDoc->sharingPairId;playlistUpdate->sharingVersion=result.deviceDoc->sharingVersion;playlistUpdate->sharingActive=result.deviceDoc->sharingActive; }
                }
                break;
            case CloudOperation::ASSET_FETCH: {
                String id=result.resourceId;
                if (!stagedAssetInFlight.isEmpty() && id==stagedAssetInFlight) {
                    bool valid = result.success && result.assetData && playlistUpdate &&
                        (result.assetData->unchanged
                            ? playlistUpdate->acceptUnchanged(id)
                            : playlistUpdate->accept(id, std::move(result.assetData->content)));
                    stagedAssetInFlight="";
                    if (!valid) {
                        playlistUpdate.reset();
                        Serial.println(F("[Config] Download failed; preserved working playlist and cache"));
                    }
                } else {
                    if (result.success && result.assetData) {
                        if (!result.assetData->unchanged && result.assetData->content.isValid()) {
                            renderAsset.resetAnimation();assetCache.addAsset(std::move(result.assetData->content));lastFailedRuntimeAssetId="";
                        } else lastFailedRuntimeAssetId=id;
                    } else lastFailedRuntimeAssetId=id;
                    pendingRuntimeAssetId="";
                }
                break;
            }

            default:
                break;
        }

        delete result.deviceDoc;
        delete result.assetData;
        delete result.pairState;
        delete result.pairSnapshot;
        delete result.pairSend;
        delete result.pairMeta;
        delete result.screens;
    }
}

void syncTime() {
    if (WiFi.isConnected() && timeSync.shouldSync()) {
        timeSync.sync(nullptr);
    }
}
