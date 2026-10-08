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
        Serial.println(F("[NVS] Failed to open namespace"));
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
    Serial.println(F("[NVS] Saved Wi-Fi SSID"));
}

void NvsStore::setWifiPass(const String& pass) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_WIFI_PASS, pass);
    Serial.println(F("[NVS] Saved Wi-Fi password"));
}

bool NvsStore::getDeviceId(String& deviceId) {
    if (!initialized) return false;
    deviceId = prefs.getString(NVS_KEY_DEVICE_ID, "");
    return deviceId.length() > 0;
}

void NvsStore::setDeviceId(const String& deviceId) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_DEVICE_ID, deviceId);
    Serial.print(F("[NVS] Saved device ID: "));
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
        Serial.print(F("[NVS] Generated new device ID: "));
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
    Serial.print(F("[NVS] Saved claimed UID: "));
    Serial.println(uid);
}

bool NvsStore::isProvisioned() {
    if (!initialized) return false;
    return prefs.getBool(NVS_KEY_PROVISIONED, false);
}

void NvsStore::setProvisioned(bool provisioned) {
    if (!initialized) return;
    prefs.putBool(NVS_KEY_PROVISIONED, provisioned);
    Serial.print(F("[NVS] Set provisioned: "));
    Serial.println(provisioned);
}

uint8_t NvsStore::getBrightness() {
    if (!initialized) return DEFAULT_BRIGHTNESS;
    return prefs.getUChar(NVS_KEY_BRIGHTNESS, DEFAULT_BRIGHTNESS);
}

void NvsStore::setBrightness(uint8_t brightness) {
    if (!initialized) return;
    prefs.putUChar(NVS_KEY_BRIGHTNESS, brightness);
    Serial.print(F("[NVS] Saved brightness: "));
    Serial.println(brightness);
}

bool NvsStore::getTzPosix(String& tz) {
    if (!initialized) return false;
    tz = prefs.getString(NVS_KEY_TZ_POSIX, "");
    return tz.length() > 0;
}

void NvsStore::setTzPosix(const String& tz) {
    if (!initialized) return;
    prefs.putString(NVS_KEY_TZ_POSIX, tz);
    Serial.print(F("[NVS] Saved timezone: "));
    Serial.println(tz);
}

// Defaults match a device that has never been given a schedule: disabled, so
// nothing dims until the owner asks for it.
void NvsStore::getSleepSettings(SleepSettings& sleep) {
    if (!initialized) {
        sleep = SleepSettings();
        return;
    }
    sleep.enabled = prefs.getBool(NVS_KEY_SLEEP_ENABLED, false);
    sleep.startMinute = prefs.getUShort(NVS_KEY_SLEEP_START, 0);
    sleep.endMinute = prefs.getUShort(NVS_KEY_SLEEP_END, 0);
    sleep.brightness = prefs.getUChar(NVS_KEY_SLEEP_BRIGHT, DEFAULT_SLEEP_BRIGHTNESS);
}

void NvsStore::setSleepSettings(const SleepSettings& sleep) {
    if (!initialized) return;
    prefs.putBool(NVS_KEY_SLEEP_ENABLED, sleep.enabled);
    prefs.putUShort(NVS_KEY_SLEEP_START, (uint16_t)sleep.startMinute);
    prefs.putUShort(NVS_KEY_SLEEP_END, (uint16_t)sleep.endMinute);
    prefs.putUChar(NVS_KEY_SLEEP_BRIGHT, sleep.brightness);
    Serial.print(F("[NVS] Saved sleep window: "));
    Serial.print(sleep.enabled ? "on " : "off ");
    Serial.print(sleep.startMinute);
    Serial.print(F("-"));
    Serial.print(sleep.endMinute);
    Serial.print(F(" @"));
    Serial.println(sleep.brightness);
}

void NvsStore::factoryReset() {
    if (!initialized) return;
    
    // Clear Wi-Fi and provisioning, keep deviceId
    prefs.remove(NVS_KEY_WIFI_SSID);
    prefs.remove(NVS_KEY_WIFI_PASS);
    prefs.remove(NVS_KEY_CLAIMED_UID);
    prefs.remove(NVS_KEY_TZ_POSIX);
    prefs.putBool(NVS_KEY_PROVISIONED, false);
    
    Serial.println(F("[NVS] Factory reset complete (deviceId preserved)"));
}

void NvsStore::fullReset() {
    if (!initialized) return;
    
    // Clear everything
    prefs.clear();
    Serial.println(F("[NVS] Full reset complete (all data cleared)"));
}

uint64_t NvsStore::reserveSendSequence(){
    uint64_t next=prefs.getULong64("sendSeq",0)+1;
    if(next>9007199254740991ULL || prefs.putULong64("sendSeq",next)!=sizeof(next))return 0;
    return next;
}
uint64_t NvsStore::getHandledSequence(const String& pairId){
    // One atomic record avoids a reboot observing a new pair with an old counter.
    String record=prefs.getString("pairHandled","");int colon=record.lastIndexOf(':');
    if(colon<0||record.substring(0,colon)!=pairId)return 0;
    return strtoull(record.substring(colon+1).c_str(),nullptr,10);
}
bool NvsStore::setHandledSequence(const String& pairId,uint64_t sequence){
    char number[24];snprintf(number,sizeof(number),"%llu",(unsigned long long)sequence);
    String record=pairId+":"+number;return prefs.putString("pairHandled",record)==record.length();
}
