#include "WifiManager.h"
#include <cassert>
#include <iostream>
unsigned long fakeMillis = 100;
int main() {
    WifiManager manager;
    assert(!manager.begin("", "") && !manager.shouldRetry());
    assert(manager.begin("saved-ssid", "password"));
    assert(!WiFi.autoReconnect && !WiFi.sleep);
    // First boot: no connection has ever succeeded. Keep retrying for an hour.
    for (unsigned i = 0; i < 36000; ++i) {
        fakeMillis += 100;
        manager.update();
    }
    assert(manager.getFailureCount() > 10 && WiFi.begins > 40 && ESP.restarts == 0);
    assert(manager.shouldRetry());
    WiFi.link = WL_CONNECTED;
    manager.update();
    assert(manager.getFailureCount() == 0);
    manager.requestReconnect();
    manager.update();
    assert(!manager.isConnected());
    const auto begins = WiFi.begins;
    // Runtime outage also keeps retrying and preserves credentials.
    WiFi.beginResult = WL_CONNECT_FAILED;
    for (unsigned i = 0; i < 36000; ++i) {
        fakeMillis += 100;
        manager.update();
    }
    assert(WiFi.begins > begins + 40 && manager.getFailureCount() > 10);
    assert(ESP.restarts == 0 && manager.getSsid() == "saved-ssid");
    WiFi.link = WL_CONNECTED;
    manager.update();
    assert(manager.isConnected() && manager.getFailureCount() == 0);
    std::cout << "Wi-Fi tests passed: indefinite boot/runtime retries, recovery, no restart\n";
}
