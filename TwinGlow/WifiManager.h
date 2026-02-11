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
    
    void attemptConnection();
    unsigned long calculateBackoffDelay();
};

#endif // WIFI_MANAGER_H
