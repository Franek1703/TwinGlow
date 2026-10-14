#pragma once
#include "Arduino.h"
enum wl_status_t { WL_DISCONNECTED, WL_CONNECTED, WL_CONNECT_FAILED };
enum { WIFI_OFF, WIFI_STA, ARDUINO_EVENT_WIFI_STA_DISCONNECTED, ARDUINO_EVENT_WIFI_STA_GOT_IP,
       ARDUINO_EVENT_WIFI_STA_CONNECTED, WIFI_ALL_CHANNEL_SCAN, WIFI_CONNECT_AP_BY_SIGNAL };
constexpr uint8_t WIFI_REASON_AUTH_EXPIRE=2;
using WiFiEvent_t = int;
using wifi_err_reason_t = int;
struct WiFiEventInfo_t { struct { uint8_t reason; int8_t rssi; uint8_t bssid[6]; } wifi_sta_disconnected; };
struct IPAddress {};
struct WifiMock {
    wl_status_t link = WL_DISCONNECTED, beginResult = WL_DISCONNECTED;
    unsigned begins = 0, disconnects = 0;
    bool autoReconnect = true, sleep = true;
    bool interfaceHasIp = true;
    bool modeSuccess = true, offSuccess = true;
    int scanMethod = -1, sortMethod = -1;
    void (*callback)(WiFiEvent_t, WiFiEventInfo_t) = nullptr;
    wl_status_t status() const { return link; }
    bool isConnected() const { return link == WL_CONNECTED && interfaceHasIp; }
    IPAddress localIP() const { return {}; }
    bool mode(int m) { return modeSuccess && (m != WIFI_OFF || offSuccess); }
    bool setAutoReconnect(bool v) { autoReconnect = v; return true; }
    bool setSleep(bool v) { sleep = v; return true; }
    void setScanMethod(int v) { scanMethod = v; }
    void setSortMethod(int v) { sortMethod = v; }
    void onEvent(void (*fn)(WiFiEvent_t, WiFiEventInfo_t)) { callback = fn; }
    wl_status_t begin(const char*, const char*) { ++begins; return beginResult; }
    void disconnect(bool = false, bool = false, unsigned = 0) { ++disconnects; link = WL_DISCONNECTED; }
    const char* disconnectReasonName(wifi_err_reason_t) { return "test"; }
    void emitDisconnect(uint8_t reason) {
        link = WL_DISCONNECTED;
        WiFiEventInfo_t info{}; info.wifi_sta_disconnected.reason = reason;
        info.wifi_sta_disconnected.rssi = -60;
        info.wifi_sta_disconnected.bssid[5] = 42;
        callback(ARDUINO_EVENT_WIFI_STA_DISCONNECTED, info);
    }
};
inline WifiMock WiFi;
