#include "WifiManager.h"
#include "esp_wifi.h"
#include <cassert>
#include <iostream>
unsigned long fakeMillis = 100;
constexpr uint8_t bgn = WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N;
constexpr uint8_t bg = WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G;

void expire(WifiManager& manager, uint8_t reason = WIFI_REASON_AUTH_EXPIRE) {
    const auto starts = WiFi.begins;
    // Duplicate SDK events within one attempt must not advance the profile.
    WiFi.emitDisconnect(reason);
    WiFi.emitDisconnect(reason);
    fakeMillis += 10000;
    manager.update();
    assert(WiFi.begins == starts);
    fakeMillis += 10000;
    manager.update();
}
void retry(WifiManager& manager) {
    const auto configs = radioMock.configurations;
    fakeMillis += 60000;
    const auto before = fakeMillis;
    manager.update(); // Tear down on this pass, no waits or new begin().
    assert(fakeMillis == before && radioMock.configurations == configs);
    fakeMillis += WIFI_TEARDOWN_SETTLE_MS;
    manager.update();
    assert(radioMock.configurations == configs + 1);
    assert(!WiFi.autoReconnect && !WiFi.sleep);
    assert(WiFi.scanMethod == WIFI_ALL_CHANNEL_SCAN);
    assert(WiFi.sortMethod == WIFI_CONNECT_AP_BY_SIGNAL);
}
int main() {
    WifiManager manager;
    assert(manager.begin("saved-ssid", "password"));
    assert(radioMock.protocols == bgn);
    assert(WiFi.scanMethod == WIFI_ALL_CHANNEL_SCAN);
    for (int attempt = 1; attempt <= 8; ++attempt) {
        expire(manager);
        assert(manager.getFailureCount() == attempt);
        retry(manager);
        // Attempt 4 first uses compatibility, then 5 normal, 6 compatibility.
        const bool compatibility = attempt >= 3 && attempt % 2 != 0;
        assert(radioMock.protocols == (compatibility ? bg : bgn));
    }
    // Not finding the AP is not an authentication failure. Recover with the
    // normal profile (also needed if an AP only supports 802.11n).
    expire(manager, 201);
    retry(manager);
    assert(radioMock.protocols == bgn);
    for (int i = 0; i < 3; ++i) { expire(manager); retry(manager); }
    WiFi.link = WL_CONNECTED;
    manager.update();
    assert(manager.getFailureCount() == 0);
    WiFi.emitDisconnect(WIFI_REASON_AUTH_EXPIRE);
    manager.update();
    retry(manager);
    assert(radioMock.protocols == bgn); // A runtime outage starts fresh.
    assert(ESP.restarts == 0 && manager.getSsid() == "saved-ssid");

    // A failed mode-off must not issue a new connect against an active radio.
    expire(manager);
    const auto starts = WiFi.begins;
    WiFi.offSuccess = false;
    fakeMillis += 60000; manager.update();
    fakeMillis += WIFI_TEARDOWN_SETTLE_MS; manager.update();
    assert(WiFi.begins == starts);
    WiFi.offSuccess = true;
    retry(manager);
    assert(WiFi.begins == starts + 1);

    WiFi = WifiMock{};
    radioMock = RadioMock{};
    radioMock.protocolError = -1;
    WifiManager protocolFailure;
    assert(protocolFailure.begin("saved-ssid", "password"));
    assert(WiFi.begins == 0 && protocolFailure.getFailureCount() == 1);
    radioMock.protocolError = ESP_OK;
    retry(protocolFailure);
    assert(WiFi.begins == 1);

    WiFi = WifiMock{}; radioMock = RadioMock{};
    radioMock.bandwidthError = -1;
    WifiManager bandwidthFailure;
    assert(bandwidthFailure.begin("saved-ssid", "password"));
    assert(WiFi.begins == 0 && bandwidthFailure.getFailureCount() == 1);
    radioMock.bandwidthError = ESP_OK;
    retry(bandwidthFailure);
    assert(WiFi.begins == 1 && ESP.restarts == 0);

    WiFi = WifiMock{}; radioMock = RadioMock{};
    WiFi.modeSuccess = false;
    WifiManager initializationFailure;
    assert(initializationFailure.begin("saved-ssid", "password"));
    assert(WiFi.begins == 0 && initializationFailure.getFailureCount() == 1);
    WiFi.modeSuccess = true;
    retry(initializationFailure);
    assert(WiFi.begins == 1 && ESP.restarts == 0);
    std::cout << "Wi-Fi recovery tests passed: full scan, 20s budget, auth profiles, duplicates, driver failures\n";
}
