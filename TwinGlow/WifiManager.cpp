#include "WifiManager.h"
#include <limits.h>
#include <esp_wifi.h>

namespace {
// Full-channel selection can try several APs with the same SSID. Give that
// work enough time even with an older, ignored Config.h specifying 10 seconds.
constexpr unsigned long kMinimumConnectBudgetMs = 20000;
constexpr uint8_t kAuthFailuresBeforeCompatibility = 3;
}

WifiManager* WifiManager::activeInstance = nullptr;

WifiManager::WifiManager() 
    : lastAttemptMs(0), retryDelayMs(WIFI_RETRY_QUICK_DELAY_MS), failureCount(0),
      quickRetryCount(0), consecutiveAuthFailures(0), compatibilityRadio(false),
      attemptAuthExpired(false), attemptAssociated(false),
      teardownStartedMs(0), teardownPending(false),
      connecting(false),
      wasConnected(false), everConnected(false), reconnectRequested(false),
      disconnectEventPending(false), gotIpEventPending(false),
      lastDisconnectReason(0), lastDisconnectRssi(0), lastDisconnectBssid{},
      eventHandlerRegistered(false) {
}

bool WifiManager::begin(const String& ssid, const String& password) {
    currentSsid = ssid;
    currentPassword = password;
    failureCount = 0;
    quickRetryCount = 0;
    consecutiveAuthFailures = 0;
    retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
    connecting = false;
    teardownPending = false;
    wasConnected = false;
    everConnected = false;
    
    if (ssid.length() == 0) {
        Serial.println(F("[WiFi] No SSID provided"));
        return false;
    }
    
    Serial.print(F("[WiFi] Connecting to: "));
    Serial.println(ssid);
    
    // Kept for diagnostics only - the retry/backoff path lives in update().
    if (!eventHandlerRegistered) {
        activeInstance = this;
        WiFi.onEvent(handleWiFiEvent);
        eventHandlerRegistered = true;
    }

    finishConnectionAttempt();
    
    return true;
}

void WifiManager::update() {
    logPendingEvents();

    // Handled before the isConnected() branch below on purpose: the cloud
    // worker raises this precisely when the station still reports
    // WL_CONNECTED but nothing routes, which is the case that branch would
    // otherwise treat as healthy and return from.
    //
    // Only the link is dropped here. The runtime-loss path further down sees
    // it on a later pass and owns the retry, so WiFi.begin() keeps exactly one
    // call site and cannot race a caller on the other core.
    if (reconnectRequested) {
        reconnectRequested = false;
        Serial.println(F("[WiFi] Cycle requested; dropping the station session"));
        WiFi.disconnect(false, false, 0);
        connecting = false;
        // Drop any half-finished retry too, so the settle window that is
        // already running cannot fire its begin() against this fresh drop.
        teardownPending = false;
        return;
    }

    unsigned long now = millis();
    if (isConnected()) {
        if (!wasConnected) {
            Serial.print(F("[WiFi] Connected! IP: "));
            Serial.println(WiFi.localIP());
#ifdef WIFI_MAX_TX_POWER_QUARTER_DBM
            // Reapply the explicit limit after the AP's country information
            // has been processed as well. Failure is logged, never a reason
            // to discard an already working association.
            const esp_err_t powerError = esp_wifi_set_max_tx_power(WIFI_MAX_TX_POWER_QUARTER_DBM);
            if (powerError != ESP_OK) {
                Serial.print(F("[WiFi] TX limit after association failed: "));
                Serial.println((int)powerError);
            }
#endif
            int8_t power = 0;
            if (esp_wifi_get_max_tx_power(&power) == ESP_OK) {
                Serial.print(F("[WiFi] TX limit after association: "));
                Serial.print(power / 4.0f);
                Serial.println(F("dBm"));
            }
            if (everConnected) {
                Serial.println(F("[WiFi] Runtime connection restored; cached screen stayed active"));
            }
        }

        wasConnected = true;
        everConnected = true;
        connecting = false;
        teardownPending = false;
        failureCount = 0;
        quickRetryCount = 0;
        consecutiveAuthFailures = 0;
        retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
        return;
    }

    if (wasConnected) {
        // A runtime loss starts a fresh quick-retry sequence. Do not transition
        // the FSM or touch the matrix: local content continues to render.
        wasConnected = false;
        connecting = false;
        teardownPending = false;
        failureCount = 0;
        quickRetryCount = 0;
        consecutiveAuthFailures = 0;
        retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
        lastAttemptMs = now;
        Serial.println(F("[WiFi] Runtime connection lost; keeping cached screen active"));
    }

    // Second half of a retry: restart the station after the settle window.
    // This resets local driver state; it cannot guarantee that the AP accepts
    // a new authentication attempt.
    if (teardownPending) {
        if (now - teardownStartedMs < WIFI_TEARDOWN_SETTLE_MS) return;
        teardownPending = false;
        finishConnectionAttempt();
        return;
    }

    if (connecting) {
        const unsigned long timeoutMs = max(
            (unsigned long)WIFI_CONNECT_ATTEMPT_TIMEOUT_MS, kMinimumConnectBudgetMs);
        if (now - lastAttemptMs < timeoutMs) return;

        const unsigned long elapsedMs = now - lastAttemptMs;
        portENTER_CRITICAL(&eventMux);
        const bool authExpired = attemptAuthExpired;
        const bool associated = attemptAssociated;
        portEXIT_CRITICAL(&eventMux);
        recordFailedAttempt(true);

        Serial.print(F("[WiFi] Connection attempt timed out; failures="));
        Serial.println(failureCount);
        Serial.print(F("[WiFi] Attempt phase="));
        Serial.print(associated ? F("associated without IP") : F("authentication/association"));
        Serial.print(F(" authExpireSeen="));
        Serial.print(authExpired);
        Serial.print(F(" elapsedMs="));
        Serial.println(elapsedMs);
        if (shouldRetry()) {
            Serial.print(F("[WiFi] Next retry in "));
            Serial.print(retryDelayMs);
            Serial.println(F("ms"));
        }
        return;
    }

    if (shouldRetry() && now - lastAttemptMs >= retryDelayMs) {
        attemptConnection();
    }
}

// First half of a retry. A plain WiFi.disconnect() leaves the driver running.
// Passing wifioff=true routes through STA.end() to restart the local radio
// state. It is a recovery step, not proof that stale state caused AUTH_EXPIRE.
void WifiManager::attemptConnection() {
    Serial.print(F("[WiFi] Attempt "));
    Serial.print(failureCount + 1);
    Serial.print(F(": cycling the radio before connecting to "));
    Serial.print(currentSsid);
    Serial.print(F("; heap="));
    Serial.print(ESP.getFreeHeap());
    Serial.print(F(" largestBlock="));
    Serial.println(ESP.getMaxAllocHeap());

    // timeoutLength=0 keeps this non-blocking; the settle window in update()
    // stands in for the wait, because this also runs from RUNNING where button
    // scanning must remain responsive.
    WiFi.disconnect(true, false, 0);
    // WiFiSTAClass::disconnect() bails out before STA.end() if
    // esp_wifi_disconnect() rejects the call, which it does when the station is
    // already stopped. Setting the mode explicitly makes the teardown
    // unconditional; espWiFiStop() underneath it does not block.
    if (!WiFi.mode(WIFI_OFF)) {
        recordFailedAttempt(false);
        Serial.println(F("[WiFi] Radio teardown failed; deferring retry"));
        return;
    }

    connecting = false;
    teardownPending = true;
    teardownStartedMs = millis();
    lastAttemptMs = teardownStartedMs;
}

void WifiManager::finishConnectionAttempt() {
    Serial.print(F("[WiFi] Connecting to "));
    Serial.println(currentSsid);

    const bool configured = configureStation();
    portENTER_CRITICAL(&eventMux);
    attemptAuthExpired = false;
    attemptAssociated = false;
    portEXIT_CRITICAL(&eventMux);
    connecting = true;
    lastAttemptMs = millis();
    wl_status_t status = configured ? WiFi.begin(
        currentSsid.c_str(), currentPassword.length() > 0 ? currentPassword.c_str() : NULL)
        : WL_CONNECT_FAILED;

    // The teardown above deinitialises the driver, so this begin() has to run
    // esp_wifi_init() again and that wants a sizeable contiguous block. When it
    // cannot get one the call fails outright and the station never even reaches
    // the air - which looks exactly like an access point refusing us unless the
    // return value is checked. Fail the attempt now rather than spending
    // WIFI_CONNECT_ATTEMPT_TIMEOUT_MS waiting for a connection nobody asked for.
    if (status == WL_CONNECT_FAILED) {
        recordFailedAttempt(false);
        Serial.print(configured ? F("[WiFi] begin() failed to start the station; failures=")
                                : F("[WiFi] Station configuration failed; failures="));
        Serial.print(failureCount);
        Serial.print(F(" largestBlock="));
        Serial.println(ESP.getMaxAllocHeap());
        return;
    }

    connecting = true;
    lastAttemptMs = millis();
}

bool WifiManager::configureStation() {
    if (!WiFi.mode(WIFI_STA)) {
        Serial.println(F("[WiFi] Could not enable station mode"));
        return false;
    }
    // Reapply after every driver restart. Arduino also has a one-time initial
    // retry independent of this flag; later retries belong to this manager.
    if (!WiFi.setAutoReconnect(false) || !WiFi.setSleep(false)) {
        Serial.println(F("[WiFi] Could not disable automatic reconnect/modem sleep"));
        return false;
    }
    // FAST_SCAN stops at the first matching SSID, which may be a failing
    // repeater. The driver can try every matching AP with ALL_CHANNEL_SCAN.
    WiFi.setScanMethod(WIFI_ALL_CHANNEL_SCAN);
    WiFi.setSortMethod(WIFI_CONNECT_AP_BY_SIGNAL);

    // A recovery hypothesis, not a diagnosis: alternate legacy modulation
    // with the normal profile after repeated auth timeouts. This preserves
    // WPA2/WPA3 security and also permits recovery on an n-only access point.
    compatibilityRadio = consecutiveAuthFailures >= kAuthFailuresBeforeCompatibility &&
        (failureCount % 2 != 0);
    const uint8_t protocols = WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G |
        (compatibilityRadio ? 0 : WIFI_PROTOCOL_11N);
    esp_err_t protocolError = esp_wifi_set_protocol(WIFI_IF_STA, protocols);
    esp_err_t bandwidthError = esp_wifi_set_bandwidth(WIFI_IF_STA, WIFI_BW_HT20);
    if (protocolError != ESP_OK || bandwidthError != ESP_OK) {
        Serial.print(F("[WiFi] Radio configuration failed: protocol="));
        Serial.print((int)protocolError);
        Serial.print(F(" bandwidth="));
        Serial.println((int)bandwidthError);
        return false;
    }
#ifdef WIFI_MAX_TX_POWER_QUARTER_DBM
    // An explicit, optional limit for controlled RF/power comparisons. Never
    // infer a power fault from AUTH_EXPIRE or lower TX automatically.
    static_assert(WIFI_MAX_TX_POWER_QUARTER_DBM >= 8 && WIFI_MAX_TX_POWER_QUARTER_DBM <= 84,
                  "Wi-Fi TX power must be 8..84 quarter-dBm units");
    const esp_err_t powerError = esp_wifi_set_max_tx_power(WIFI_MAX_TX_POWER_QUARTER_DBM);
    if (powerError != ESP_OK) {
        Serial.print(F("[WiFi] Could not apply TX power limit: "));
        Serial.println((int)powerError);
        return false;
    }
#endif
    int8_t power = 0;
    const esp_err_t powerReadError = esp_wifi_get_max_tx_power(&power);
    Serial.print(F("[WiFi] Station profile="));
    Serial.print(compatibilityRadio ? F("b/g compatibility") : F("b/g/n"));
    Serial.print(F(" scan=all-channels bandwidth=20MHz sleep=off autoReconnect=off txLimit="));
    if (powerReadError == ESP_OK) {
        Serial.print(power / 4.0f);
        Serial.println(F("dBm"));
    } else {
        Serial.print(F("unavailable error="));
        Serial.println((int)powerReadError);
    }
    return true;
}

void WifiManager::recordFailedAttempt(bool authenticationAttempt) {
    if (failureCount < INT_MAX - 1) ++failureCount;
    if (quickRetryCount < WIFI_RETRY_QUICK_COUNT + 4) ++quickRetryCount;
    // Several AUTH_EXPIRE events within one SDK attempt count as one failure.
    portENTER_CRITICAL(&eventMux);
    const bool authExpired = attemptAuthExpired;
    portEXIT_CRITICAL(&eventMux);
    if (authenticationAttempt && authExpired) {
        if (consecutiveAuthFailures < 255) ++consecutiveAuthFailures;
    } else {
        consecutiveAuthFailures = 0;
    }
    connecting = false;
    retryDelayMs = calculateBackoffDelay();
    lastAttemptMs = millis();
}

unsigned long WifiManager::calculateBackoffDelay() {
    if (quickRetryCount < WIFI_RETRY_QUICK_COUNT) {
        return WIFI_RETRY_QUICK_DELAY_MS;
    }
    
    // Exponential backoff: 5s -> 10s -> 30s -> 60s
    int backoffIndex = quickRetryCount - WIFI_RETRY_QUICK_COUNT;
    unsigned long delays[] = {5000, 10000, 30000, 60000};
    
    if (backoffIndex < 4) {
        return delays[backoffIndex];
    }
    
    return WIFI_RETRY_BACKOFF_MAX_MS;
}

bool WifiManager::shouldRetry() const {
    return !currentSsid.isEmpty();
}

void WifiManager::handleWiFiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
    WifiManager* manager = activeInstance;
    if (manager == nullptr) return;

    portENTER_CRITICAL(&manager->eventMux);
    if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
        manager->lastDisconnectReason = info.wifi_sta_disconnected.reason;
        manager->lastDisconnectRssi = info.wifi_sta_disconnected.rssi;
        memcpy(manager->lastDisconnectBssid, info.wifi_sta_disconnected.bssid, 6);
        if (info.wifi_sta_disconnected.reason == WIFI_REASON_AUTH_EXPIRE) {
            manager->attemptAuthExpired = true;
        }
        manager->disconnectEventPending = true;
    } else if (event == ARDUINO_EVENT_WIFI_STA_CONNECTED) {
        manager->attemptAssociated = true;
    } else if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
        manager->gotIpEventPending = true;
    }
    portEXIT_CRITICAL(&manager->eventMux);
}

void WifiManager::logPendingEvents() {
    portENTER_CRITICAL(&eventMux);
    const bool disconnected = disconnectEventPending;
    const bool gotIp = gotIpEventPending;
    const uint8_t reason = lastDisconnectReason;
    const int8_t rssi = lastDisconnectRssi;
    uint8_t mac[6];
    memcpy(mac, lastDisconnectBssid, 6);
    disconnectEventPending = false;
    gotIpEventPending = false;
    portEXIT_CRITICAL(&eventMux);
    if (disconnected) {
        Serial.print(F("[WiFi] STA disconnected: reason="));
        Serial.print(reason);
        Serial.print(F(" ("));
        Serial.print(WiFi.disconnectReasonName((wifi_err_reason_t)reason));
        Serial.print(F(") rssi="));
        Serial.print((int)rssi);
        Serial.print(F("dBm driverStatus="));
        Serial.print((int)WiFi.status());
        Serial.print(F(" connectedWithIp="));
        Serial.print(isConnected());
        char bssid[18];
        snprintf(bssid, sizeof(bssid), "%02X:%02X:%02X:%02X:%02X:%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        Serial.print(F(" bssid="));
        Serial.println(bssid);
    }

    if (gotIp) {
        Serial.print(F("[WiFi] STA got IP: "));
        Serial.println(WiFi.localIP());
    }
}
