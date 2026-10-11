#include "WifiManager.h"
#include "ConnectivityStatus.h"
#include <cassert>
#include <iostream>
unsigned long fakeMillis = 100;
enum class DeviceState { BOOT, LOAD_NVS, PROVISIONING_BLE, ERROR_RECOVERY, WIFI_CONNECTING, TIME_SYNC, RUNNING };
struct Fsm {
    DeviceState state = DeviceState::WIFI_CONNECTING;
    DeviceState getState() { return state; }
    void transition(DeviceState next) { state = next; }
} fsm;
struct Nvs {
    bool configured = false;
    unsigned resets = 0;
    bool getWifiSsid(String& out) { out = configured ? "saved-ssid" : ""; return configured; }
    void getWifiPass(String& out) { out = "password"; }
    void factoryReset() { configured = false; ++resets; }
} nvs;
struct Matrix {
    // The held image/frame stays intact through all connectivity transitions.
    const unsigned content = 0xEDAB63;
    unsigned shows = 0;
    ConnectivityStatus status = ConnectivityStatus::Online;
    bool enabled = false;
    bool setConnectivityStatus(ConnectivityStatus next, bool enable) {
        bool changed = next != status || enabled != enable;
        status = next; enabled = enable; return changed;
    }
    void show() { ++shows; }
} matrix;
struct Cloud {
    bool started = false, accepts = true;
    unsigned requests = 0, confirmationsReset = 0;
    ConnectionHealth health;
    bool isStarted() { return started; }
    bool requestConfigCheck() { ++requests; return accepts; }
    void resetHealthConfirmation() { health.resetConfirmation(); ++confirmationsReset; }
    ConnectivityStatus connectivityStatus(bool connected) { return health.status(connected, millis()); }
} cloudWorker;
enum class ButtonId { ACTION };
enum class ButtonPressType { NONE, VERY_LONG };
struct Buttons {
    ButtonPressType event = ButtonPressType::NONE;
    ButtonPressType getPressType(ButtonId) { return event; }
    void clearEvent(ButtonId) { event = ButtonPressType::NONE; }
} buttons;
WifiManager wifiManager;
#include "main-runtime.inc"
int main() {
    handleWifiConnecting();
    assert(fsm.state == DeviceState::PROVISIONING_BLE && WiFi.begins == 0);
    updateConnectivityIndicator(); assert(!matrix.enabled);
    fsm.state = DeviceState::WIFI_CONNECTING; nvs.configured = true;
    for (unsigned i=0; i<36000; ++i) { fakeMillis+=100; handleWifiConnecting(); }
    assert(fsm.state==DeviceState::WIFI_CONNECTING && ESP.restarts==0);
    updateConnectivityIndicator();
    assert(matrix.enabled && matrix.status==ConnectivityStatus::WifiOffline);
    WiFi.link=WL_CONNECTED; handleWifiConnecting();
    assert(fsm.state==DeviceState::TIME_SYNC);
    updateConnectivityIndicator();
    assert(matrix.status==ConnectivityStatus::FirebaseUnavailable);
    fsm.state=DeviceState::RUNNING; cloudWorker.started=true; cloudWorker.accepts=false;
    updateConnectivityIndicator(); const auto requests=cloudWorker.requests;
    cloudWorker.accepts=true; updateConnectivityIndicator();
    assert(cloudWorker.requests==requests+1); // Retry deferred confirmation.
    cloudWorker.health.setAuthReady(true);
    cloudWorker.health.record(CloudService::Rtdb,true,0,millis());
    cloudWorker.health.record(CloudService::Firestore,true,0,millis());
    updateConnectivityIndicator(); assert(matrix.status==ConnectivityStatus::Online);
    auto shows=matrix.shows;
    for (unsigned i=0; i<100; ++i) updateConnectivityIndicator();
    assert(matrix.shows==shows); // No refresh/restart when the status is unchanged.
    WiFi.link=WL_DISCONNECTED; updateConnectivityIndicator();
    assert(matrix.status==ConnectivityStatus::WifiOffline && fsm.state==DeviceState::RUNNING);
    WiFi.link=WL_CONNECTED; updateConnectivityIndicator();
    assert(matrix.status==ConnectivityStatus::FirebaseUnavailable);
    assert(matrix.content==0xEDAB63 && nvs.configured && ESP.restarts==0);
    buttons.event=ButtonPressType::VERY_LONG; handleBootFactoryReset();
    assert(ESP.restarts==1 && nvs.resets==1 && !nvs.configured);
    std::cout << "Runtime tests passed: BLE only without credentials, indicators, reconnect confirmation, boot reset\n";
}
