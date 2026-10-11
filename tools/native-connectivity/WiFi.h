#pragma once
#include "Arduino.h"
enum wl_status_t { WL_DISCONNECTED, WL_CONNECTED, WL_CONNECT_FAILED };
enum { WIFI_OFF, WIFI_STA, ARDUINO_EVENT_WIFI_STA_DISCONNECTED, ARDUINO_EVENT_WIFI_STA_GOT_IP };
using WiFiEvent_t = int;
using wifi_err_reason_t = int;
struct WiFiEventInfo_t { struct { uint8_t reason; } wifi_sta_disconnected; };
struct IPAddress {};
struct WifiMock {
    wl_status_t link = WL_DISCONNECTED, beginResult = WL_DISCONNECTED;
    unsigned begins = 0, disconnects = 0;
    bool autoReconnect = true, sleep = true;
    wl_status_t status() const { return link; }
    bool isConnected() const { return link == WL_CONNECTED; }
    IPAddress localIP() const { return {}; }
    void mode(int) {}
    void setAutoReconnect(bool v) { autoReconnect = v; }
    void setSleep(bool v) { sleep = v; }
    void onEvent(void (*)(WiFiEvent_t, WiFiEventInfo_t)) {}
    wl_status_t begin(const char*, const char*) { ++begins; return beginResult; }
    void disconnect(bool = false, bool = false, unsigned = 0) { ++disconnects; link = WL_DISCONNECTED; }
    const char* disconnectReasonName(wifi_err_reason_t) { return "test"; }
};
inline WifiMock WiFi;
