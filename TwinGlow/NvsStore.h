#ifndef NVS_STORE_H
#define NVS_STORE_H

#include <Preferences.h>
#include <Arduino.h>
#include "SleepSchedule.h"

/**
 * NVS Storage wrapper for persistent data
 * Uses ESP32 Preferences API
 */
class NvsStore {
public:
    NvsStore();
    ~NvsStore();
    
    bool begin();
    void end();
    
    // Wi-Fi credentials
    bool getWifiSsid(String& ssid);
    bool getWifiPass(String& pass);
    void setWifiSsid(const String& ssid);
    void setWifiPass(const String& pass);
    
    // Device ID (generated once, stable)
    bool getDeviceId(String& deviceId);
    void setDeviceId(const String& deviceId);
    String generateDeviceId(); // Generate new random ID
    
    // User ID (from BLE provisioning)
    bool getClaimedUid(String& uid);
    void setClaimedUid(const String& uid);
    
    // Provisioning status
    bool isProvisioned();
    void setProvisioned(bool provisioned);
    
    // Brightness (0-255)
    uint8_t getBrightness();
    void setBrightness(uint8_t brightness);

    // POSIX TZ rule (e.g. "CET-1CEST,M3.5.0,M10.5.0/3"), cached from the device
    // doc so the clock is right at boot, before Firestore is reachable.
    bool getTzPosix(String& tz);
    void setTzPosix(const String& tz);

    // Sleep window, cached from the device doc for the same reason as the
    // timezone: a boot that never reaches Firestore must still dim on schedule.
    void getSleepSettings(SleepSettings& sleep);
    void setSleepSettings(const SleepSettings& sleep);
    
    // Factory reset
    void factoryReset(); // Clear all except deviceId
    void fullReset();    // Clear everything including deviceId
    
private:
    Preferences prefs;
    bool initialized;
    
    void ensureDeviceId();
};

#endif // NVS_STORE_H
