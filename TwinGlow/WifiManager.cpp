#include "WifiManager.h"

WifiManager* WifiManager::activeInstance = nullptr;

WifiManager::WifiManager() 
    : lastAttemptMs(0), retryDelayMs(WIFI_RETRY_QUICK_DELAY_MS), failureCount(0),
      quickRetryCount(0), teardownStartedMs(0), teardownPending(false),
      offlineSinceMs(0), connecting(false), persistentReconnect(false),
      wasConnected(false), everConnected(false), reconnectRequested(false),
      disconnectEventPending(false), gotIpEventPending(false),
      lastDisconnectReason(0), eventHandlerRegistered(false) {
}

bool WifiManager::begin(const String& ssid, const String& password) {
    currentSsid = ssid;
    currentPassword = password;
    failureCount = 0;
    quickRetryCount = 0;
    retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
    connecting = false;
    teardownPending = false;
    offlineSinceMs = 0;
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

    // The core's auto-reconnect is not passive: on every reason it considers
    // retryable - AUTH_EXPIRE and GROUP_KEY_UPDATE_TIMEOUT included - its event
    // handler issues its own disconnect()/connect() pair. Left on, it raced the
    // retry below for the radio and the two kept aborting each other's
    // association, which is what turned one lost group-key handshake into an
    // endless AUTH_EXPIRE storm. update() is the only retry path now.
    WiFi.setAutoReconnect(false);

    // Modem sleep is the default on every target but the S2. A dozing radio
    // misses the AP's periodic group-key handshake and gets deauthed with
    // GROUP_KEY_UPDATE_TIMEOUT; the panel is mains-powered, so the extra ~40mA
    // costs nothing worth having the dropouts for.
    WiFi.setSleep(false);

    // Kept for diagnostics only - the retry/backoff path lives in update().
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
            if (everConnected) {
                Serial.println(F("[WiFi] Runtime connection restored; cached screen stayed active"));
            }
        }

        wasConnected = true;
        everConnected = true;
        connecting = false;
        teardownPending = false;
        offlineSinceMs = 0;
        failureCount = 0;
        quickRetryCount = 0;
        retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
        return;
    }

    if (wasConnected) {
        // A runtime loss starts a fresh quick-retry sequence. Do not transition
        // the FSM or touch the matrix: local content continues to render.
        wasConnected = false;
        connecting = false;
        teardownPending = false;
        offlineSinceMs = now;
        failureCount = 0;
        quickRetryCount = 0;
        retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
        lastAttemptMs = now;
        Serial.println(F("[WiFi] Runtime connection lost; keeping cached screen active"));
    }

    // A device that has connected once retries forever, but the station can
    // still reach a state no further begin() recovers from - an AP that expires
    // every auth leaves the retry loop running with nothing to show for it.
    // A restart is the only lever left, and it is cheap: credentials and the
    // cached playlist both survive in NVS.
    if (persistentReconnect && offlineSinceMs != 0 &&
        now - offlineSinceMs >= WIFI_OFFLINE_REBOOT_MS) {
        Serial.print(F("[WiFi] Offline for "));
        Serial.print((now - offlineSinceMs) / 1000);
        Serial.println(F("s; restarting to clear the radio"));
        Serial.flush();
        ESP.restart();
    }

    // Second half of a retry: the radio has had WIFI_TEARDOWN_SETTLE_MS with
    // the station disabled, so the supplicant state the AP had already expired
    // is gone and this begin() opens a genuinely new session.
    if (teardownPending) {
        if (now - teardownStartedMs < WIFI_TEARDOWN_SETTLE_MS) return;
        teardownPending = false;
        finishConnectionAttempt();
        return;
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

// First half of a retry. A plain WiFi.disconnect() leaves the station enabled
// and its association state intact, so a begin() issued straight afterwards
// re-offered the very session the AP had already expired - the device could
// retry for hours without ever presenting itself as a new client. Passing
// wifioff=true routes through STA.end() and takes the station down properly.
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
    WiFi.mode(WIFI_OFF);

    connecting = false;
    teardownPending = true;
    teardownStartedMs = millis();
    lastAttemptMs = teardownStartedMs;
}

void WifiManager::finishConnectionAttempt() {
    Serial.print(F("[WiFi] Connecting to "));
    Serial.println(currentSsid);

    // begin() re-enables the station on its own; the explicit mode() keeps the
    // radio-off/radio-on pairing visible at the call site.
    WiFi.mode(WIFI_STA);
    wl_status_t status = WiFi.begin(
        currentSsid.c_str(), currentPassword.length() > 0 ? currentPassword.c_str() : NULL);

    // The teardown above deinitialises the driver, so this begin() has to run
    // esp_wifi_init() again and that wants a sizeable contiguous block. When it
    // cannot get one the call fails outright and the station never even reaches
    // the air - which looks exactly like an access point refusing us unless the
    // return value is checked. Fail the attempt now rather than spending
    // WIFI_CONNECT_ATTEMPT_TIMEOUT_MS waiting for a connection nobody asked for.
    if (status == WL_CONNECT_FAILED) {
        connecting = false;
        failureCount++;
        quickRetryCount++;
        retryDelayMs = calculateBackoffDelay();
        lastAttemptMs = millis();
        Serial.print(F("[WiFi] begin() failed to start the station; failures="));
        Serial.print(failureCount);
        Serial.print(F(" largestBlock="));
        Serial.println(ESP.getMaxAllocHeap());
        return;
    }

    connecting = true;
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
    return persistentReconnect || failureCount < WIFI_MAX_FAILURES;
}

bool WifiManager::shouldEnterProvisioning() const {
    return !persistentReconnect && failureCount >= WIFI_MAX_FAILURES;
}

void WifiManager::reset() {
    WiFi.disconnect();
    connecting = false;
    teardownPending = false;
    offlineSinceMs = 0;
    failureCount = 0;
    quickRetryCount = 0;
    retryDelayMs = WIFI_RETRY_QUICK_DELAY_MS;
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
