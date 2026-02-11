#include "WifiManager.h"

WifiManager::WifiManager() 
    : lastAttemptMs(0), retryDelayMs(1000), failureCount(0), 
      quickRetryCount(0), connecting(false) {
}

bool WifiManager::begin(const String& ssid, const String& password) {
    currentSsid = ssid;
    currentPassword = password;
    failureCount = 0;
    quickRetryCount = 0;
    retryDelayMs = 1000;
    connecting = false;
    
    if (ssid.length() == 0) {
        Serial.println("[WiFi] No SSID provided");
        return false;
    }
    
    Serial.print("[WiFi] Connecting to: ");
    Serial.println(ssid);
    
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid.c_str(), password.length() > 0 ? password.c_str() : NULL);
    
    connecting = true;
    lastAttemptMs = millis();
    
    return true;
}

void WifiManager::update() {
    if (connecting) {
        if (isConnected()) {
            Serial.print("[WiFi] Connected! IP: ");
            Serial.println(WiFi.localIP());
            connecting = false;
            failureCount = 0;
            quickRetryCount = 0;
        } else {
            unsigned long now = millis();
            unsigned long elapsed = now - lastAttemptMs;
            
            // Check if connection attempt timed out
            if (elapsed > 10000) { // 10 second timeout
                Serial.println("[WiFi] Connection timeout");
                failureCount++;
                quickRetryCount++;
                
                if (shouldRetry()) {
                    retryDelayMs = calculateBackoffDelay();
                    Serial.print("[WiFi] Retrying in ");
                    Serial.print(retryDelayMs);
                    Serial.println("ms");
                    lastAttemptMs = now;
                } else {
                    connecting = false;
                }
            }
        }
    } else if (!isConnected() && shouldRetry()) {
        unsigned long now = millis();
        if (now - lastAttemptMs >= retryDelayMs) {
            attemptConnection();
        }
    }
}

void WifiManager::attemptConnection() {
    Serial.print("[WiFi] Attempt ");
    Serial.print(failureCount + 1);
    Serial.print(": Connecting to ");
    Serial.println(currentSsid);
    
    WiFi.disconnect();
    delay(100);
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
    return failureCount < WIFI_MAX_FAILURES;
}

bool WifiManager::shouldEnterProvisioning() const {
    return failureCount >= WIFI_MAX_FAILURES;
}

void WifiManager::reset() {
    WiFi.disconnect();
    connecting = false;
    failureCount = 0;
    quickRetryCount = 0;
    retryDelayMs = 1000;
}
