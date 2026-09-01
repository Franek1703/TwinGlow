#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <WiFi.h>
#include <Arduino.h>
#include "Config.h"

/**
 * Wi-Fi connection manager with retry and backoff
 * Non-blocking connection attempts
 */
class WifiManager {
public:
    WifiManager();
    
    bool begin(const String& ssid, const String& password);
    void update(); // Call in loop() for non-blocking operation

    // Initial setup gives up after WIFI_MAX_FAILURES so bad credentials can
    // return to provisioning. Once the device has connected successfully,
    // runtime recovery must continue forever using capped backoff.
    void setPersistentReconnect(bool enabled) { persistentReconnect = enabled; }
    
    // Asks for a fresh station session from another task. The request is acted
    // on inside update(), so that every WiFi.begin()/disconnect() in the
    // firmware is issued from the one task that owns the radio.
    void requestReconnect() { reconnectRequested = true; }

    bool isConnected() const { return WiFi.status() == WL_CONNECTED; }
    String getSsid() const { return currentSsid; }
    IPAddress getIpAddress() const { return WiFi.localIP(); }
    
    // Status
    int getFailureCount() const { return failureCount; }
    bool shouldRetry() const;
    bool shouldEnterProvisioning() const;
    
    void reset();
    
private:
    String currentSsid;
    String currentPassword;
    
    unsigned long lastAttemptMs;
    unsigned long retryDelayMs;
    int failureCount;
    int quickRetryCount;
    
    bool connecting;
    bool persistentReconnect;
    bool wasConnected;
    bool everConnected;

    volatile bool reconnectRequested;
    volatile bool disconnectEventPending;
    volatile bool gotIpEventPending;
    volatile uint8_t lastDisconnectReason;
    bool eventHandlerRegistered;

    static WifiManager* activeInstance;
    static void handleWiFiEvent(WiFiEvent_t event, WiFiEventInfo_t info);
    
    void attemptConnection();
    unsigned long calculateBackoffDelay();
    void logPendingEvents();
};

#endif // WIFI_MANAGER_H
