#include "WifiManager.h"
#include "esp_wifi.h"
#include <cassert>
#include <iostream>
unsigned long fakeMillis = 100;
int main() {
    WifiManager manager;
    assert(manager.begin("saved-ssid", "password"));
    assert(WiFi.begins == 1 && radioMock.power == 28);
    radioMock.power = 72; // Association/country update must retain our limit.
    WiFi.link = WL_CONNECTED; manager.update();
    assert(radioMock.power == 28);
    WiFi.emitDisconnect(2); manager.update();
    fakeMillis += 4000; manager.update();
    fakeMillis += WIFI_TEARDOWN_SETTLE_MS; manager.update();
    assert(WiFi.begins == 2 && radioMock.power == 28); // Reapplied after restart.
    WiFi = WifiMock{}; radioMock = RadioMock{};
    radioMock.powerError = -1;
    WifiManager failed;
    assert(failed.begin("saved-ssid", "password"));
    assert(WiFi.begins == 0 && failed.getFailureCount() == 1);
    radioMock.powerError = ESP_OK;
    fakeMillis += 60000; failed.update();
    fakeMillis += WIFI_TEARDOWN_SETTLE_MS; failed.update();
    assert(WiFi.begins == 1 && radioMock.power == 28 && ESP.restarts == 0);
    std::cout << "Wi-Fi TX limit tests passed: explicit setting, restart, configuration failure recovery\n";
}
