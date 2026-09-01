#include "WifiManager.h"

WifiManager* WifiManager::activeInstance = nullptr;

WifiManager::WifiManager() 
    : lastAttemptMs(0), retryDelayMs(1000), failureCount(0), 
      quickRetryCount(0), connecting(false), persistentReconnect(false),
      wasConnected(false), everConnected(false), reconnectRequested(false),
      disconnectEventPending(false), gotIpEventPending(false),
      lastDisconnectReason(0), eventHandlerRegistered(false) {
}

bool WifiManager::begin(const String& ssid, const String& password) {
    currentSsid = ssid;
    currentPassword = password;
    failureCount = 0;
    quickRetryCount = 0;
    retryDelayMs = 1000;
    connecting = false;
    persistentReconnect = false;
    wasConnected = false;
    everConnected = false;
    
    if (ssid.length() == 0) {
        Serial.println(F("[WiFi] No SSID provided"));
        return false;
    }
    
    Serial.print(F("[WiFi] Connecting to: "));
    Serial.println(ssid);
    
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);

    // Arduino's built-in auto-reconnect only retries a subset of disconnect
    // reasons. Keep the event for diagnostics; update() below supplies the
    // deterministic retry/backoff path for every runtime disconnect.
    if (!eventHandlerRegistered) {
        activeInstance = this;
        WiFi.onEvent(handleWiFiEvent);
        eventHandlerRegistered = true;
    }

    WiFi.begin(ssid.c_str(), password.length() > 0 ? password.c_str() : NULL);
    
    connecting = true;
    lastAttemptMs = millis();
    
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
        return;
    }

    unsigned long now = millis();
    if (isConnected()) {
        if (!wasConnected) {
            Serial.print(F("[WiFi] Connected! IP: "));
            Serial.println(WiFi.localIP());
            if (everConnected) {
                Serial.println(F("[WiFi] Runtime connection restored; cached screen stayed active"));
            }
        }

        wasConnected = true;
        everConnected = true;
        connecting = false;
        failureCount = 0;
        quickRetryCount = 0;
        retryDelayMs = 1000;
        return;
    }

    if (wasConnected) {
        // A runtime loss starts a fresh quick-retry sequence. Do not transition
        // the FSM or touch the matrix: local content continues to render.
        wasConnected = false;
        connecting = false;
        failureCount = 0;
        quickRetryCount = 0;
        retryDelayMs = 1000;
        lastAttemptMs = now;
        Serial.println(F("[WiFi] Runtime connection lost; keeping cached screen active"));
    }

    if (connecting) {
        if (now - lastAttemptMs < WIFI_CONNECT_ATTEMPT_TIMEOUT_MS) return;

        failureCount++;
        quickRetryCount++;
        connecting = false;
        retryDelayMs = calculateBackoffDelay();
        lastAttemptMs = now;

        Serial.print(F("[WiFi] Connection attempt timed out; failures="));
        Serial.println(failureCount);
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

void WifiManager::attemptConnection() {
    Serial.print(F("[WiFi] Attempt "));
    Serial.print(failureCount + 1);
    Serial.print(F(": Connecting to "));
    Serial.println(currentSsid);
    
    // Both calls are non-blocking. In particular, do not delay here: this also
    // runs from RUNNING, where button scanning must remain responsive.
    WiFi.disconnect(false, false, 0);
    WiFi.begin(currentSsid.c_str(), currentPassword.length() > 0 ? currentPassword.c_str() : NULL);
    
    connecting = true;
    lastAttemptMs = millis();
}

unsigned long WifiManager::calculateBackoffDelay() {
    if (quickRetryCount < WIFI_RETRY_QUICK_COUNT) {
        return 1000; // Quick retries: 1 second
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
    return persistentReconnect || failureCount < WIFI_MAX_FAILURES;
}

bool WifiManager::shouldEnterProvisioning() const {
    return !persistentReconnect && failureCount >= WIFI_MAX_FAILURES;
}

void WifiManager::reset() {
    WiFi.disconnect();
    connecting = false;
    failureCount = 0;
    quickRetryCount = 0;
    retryDelayMs = 1000;
    persistentReconnect = false;
    wasConnected = false;
    everConnected = false;
}

void WifiManager::handleWiFiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
    WifiManager* manager = activeInstance;
    if (manager == nullptr) return;

    if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
        manager->lastDisconnectReason = info.wifi_sta_disconnected.reason;
        manager->disconnectEventPending = true;
    } else if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
        manager->gotIpEventPending = true;
    }
}

void WifiManager::logPendingEvents() {
    if (disconnectEventPending) {
        uint8_t reason = lastDisconnectReason;
        disconnectEventPending = false;
        Serial.print(F("[WiFi] STA disconnected: reason="));
        Serial.print(reason);
        Serial.print(F(" ("));
        Serial.print(WiFi.disconnectReasonName((wifi_err_reason_t)reason));
        Serial.println(F(")"));
    }

    if (gotIpEventPending) {
        gotIpEventPending = false;
        Serial.print(F("[WiFi] STA got IP: "));
        Serial.println(WiFi.localIP());
    }
}
