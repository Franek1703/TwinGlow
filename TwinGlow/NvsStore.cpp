#include "NvsStore.h"
#include "Config.h"
#include <WiFi.h>

NvsStore::NvsStore() : initialized(false) {
}

NvsStore::~NvsStore() {
    end();
}

bool NvsStore::begin() {
    if (initialized) return true;
    
    if (!prefs.begin(NVS_NAMESPACE, false)) {
        Serial.println("[NVS] Failed to open namespace");
        return false;
    }
    
    initialized = true;
    ensureDeviceId();
    return true;
}

void NvsStore::end() {
    if (initialized) {
        prefs.end();
        initialized = false;
    }
}

bool NvsStore::getWifiSsid(String& ssid) {
    if (!initialized) return false;
    ssid = prefs.getString(NVS_KEY_WIFI_SSID, "");
    return ssid.length() > 0;
}

bool NvsStore::getWifiPass(String& pass) {
    if (!initialized) return false;
    pass = prefs.getString(NVS_KEY_WIFI_PASS, "");
    return true; // Empty password is valid for open networks
}

void NvsStore::setWifiSsid(const String& ssid) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_WIFI_SSID, ssid);
    Serial.println("[NVS] Saved Wi-Fi SSID");
}

void NvsStore::setWifiPass(const String& pass) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_WIFI_PASS, pass);
    Serial.println("[NVS] Saved Wi-Fi password");
}

bool NvsStore::getDeviceId(String& deviceId) {
    if (!initialized) return false;
    deviceId = prefs.getString(NVS_KEY_DEVICE_ID, "");
    return deviceId.length() > 0;
}

void NvsStore::setDeviceId(const String& deviceId) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_DEVICE_ID, deviceId);
    Serial.print("[NVS] Saved device ID: ");
    Serial.println(deviceId);
}

String NvsStore::generateDeviceId() {
    // Generate random device ID: "tg_" + 12 hex chars
    String id = "tg_";
    for (int i = 0; i < 12; i++) {
        id += String(random(0, 16), HEX);
    }
    return id;
}

void NvsStore::ensureDeviceId() {
    String deviceId;
    if (!getDeviceId(deviceId) || deviceId.length() == 0) {
        String newId = generateDeviceId();
        setDeviceId(newId);
        Serial.print("[NVS] Generated new device ID: ");
        Serial.println(newId);
    }
}

bool NvsStore::getClaimedUid(String& uid) {
    if (!initialized) return false;
    uid = prefs.getString(NVS_KEY_CLAIMED_UID, "");
    return uid.length() > 0;
}

void NvsStore::setClaimedUid(const String& uid) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_CLAIMED_UID, uid);
    Serial.print("[NVS] Saved claimed UID: ");
    Serial.println(uid);
}

bool NvsStore::isProvisioned() {
    if (!initialized) return false;
    return prefs.getBool(NVS_KEY_PROVISIONED, false);
}

void NvsStore::setProvisioned(bool provisioned) {
    if (!initialized) return;
    prefs.putBool(NVS_KEY_PROVISIONED, provisioned);
    Serial.print("[NVS] Set provisioned: ");
    Serial.println(provisioned);
}

uint8_t NvsStore::getBrightness() {
    if (!initialized) return DEFAULT_BRIGHTNESS;
    return prefs.getUChar(NVS_KEY_BRIGHTNESS, DEFAULT_BRIGHTNESS);
}

void NvsStore::setBrightness(uint8_t brightness) {
    if (!initialized) return;
    prefs.putUChar(NVS_KEY_BRIGHTNESS, brightness);
    Serial.print("[NVS] Saved brightness: ");
    Serial.println(brightness);
}

void NvsStore::factoryReset() {
    if (!initialized) return;
    
    // Clear Wi-Fi and provisioning, keep deviceId
    prefs.remove(NVS_KEY_WIFI_SSID);
    prefs.remove(NVS_KEY_WIFI_PASS);
    prefs.remove(NVS_KEY_CLAIMED_UID);
    prefs.putBool(NVS_KEY_PROVISIONED, false);
    
    Serial.println("[NVS] Factory reset complete (deviceId preserved)");
}

void NvsStore::fullReset() {
    if (!initialized) return;
    
    // Clear everything
    prefs.clear();
    Serial.println("[NVS] Full reset complete (all data cleared)");
}
