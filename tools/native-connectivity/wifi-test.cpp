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
    // AUTH_EXPIRE can leave the SDK's legacy status at WL_CONNECTED even
    // though its interface connection/IP bits have already been cleared.
    WiFi.interfaceHasIp = false;
    assert(WiFi.status() == WL_CONNECTED && !manager.isConnected());
    manager.update();
    const auto beforeExpiredAuthRetry = WiFi.begins;
    fakeMillis += WIFI_RETRY_QUICK_DELAY_MS;
    manager.update();
    fakeMillis += WIFI_TEARDOWN_SETTLE_MS;
    manager.update();
    assert(WiFi.begins == beforeExpiredAuthRetry + 1);
    assert(ESP.restarts == 0);
    WiFi.interfaceHasIp = true;
    WiFi.link = WL_CONNECTED;
    manager.update();
    assert(manager.isConnected() && manager.getFailureCount() == 0);
    std::cout << "Wi-Fi tests passed: indefinite retries, stale AUTH_EXPIRE status, recovery, no restart\n";
}
