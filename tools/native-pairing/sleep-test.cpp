#include "SleepSchedule.h"
#include <cassert>
#include <ctime>
#include <iostream>

using std::min;
using std::max;
int constrain(int value, int low, int high) { return min(high, max(low, value)); }
unsigned long fakeMillis = 10000;
time_t fakeEpoch = 1767227400; // 2026-01-01 00:30 UTC
time_t testTime(time_t*) { return fakeEpoch; }
namespace TimeSync {
bool valid = true;
bool isTimeValid() { return valid; }
}
struct Matrix {
    uint8_t brightness = 128;
    unsigned clears = 0, shows = 0;
    void setBrightness(uint8_t value) { brightness = value ? value : 1; }
    uint8_t getBrightness() { return brightness; }
    void clear() { ++clears; }
    void show() { ++shows; }
} matrix;
struct Nvs {
    uint8_t brightness = 128;
    unsigned brightnessWrites = 0, sleepWrites = 0;
    uint8_t getBrightness() { return brightness; }
    void setBrightness(uint8_t value) { brightness = value; ++brightnessWrites; }
    void setSleepSettings(const SleepSettings&) { ++sleepWrites; }
} nvs;
struct Renderer {
    unsigned resets = 0;
    void resetAnimation() { ++resets; }
} renderAsset, receivedRenderer;
struct Worker {
    unsigned writes = 0;
    void requestBrightnessWrite(uint8_t) { ++writes; }
} worker;
struct DeviceDoc {
    int brightness = 128;
    bool hasSleep = true;
    SleepSettings sleep;
};
SleepSettings sleepSettings;
bool sleepActive = false;
int sleepBrightnessOverride = -1;
int lastCloudBrightness = -1;
unsigned long lastSleepCheckMs = 0;
constexpr unsigned long SLEEP_CHECK_INTERVAL_MS = 15000;
class ButtonActions {
public:
    Nvs* nvs = &::nvs;
    Matrix* matrix = &::matrix;
    Worker* cloudWorker = &worker;
    bool (*onBrightnessChange)(bool) = nullptr;
    void handleBrightnessChange(bool increase);
};
#define time testTime
#include "sleep-runtime.inc"
#undef time
#include "brightness-button.inc"

int main() {
    setenv("TZ", "UTC", 1);
    tzset();
    DeviceDoc doc;
    doc.sleep.enabled = true;
    doc.sleep.startMinute = 23 * 60;
    doc.sleep.endMinute = 7 * 60;
    doc.sleep.brightness = 0;
    applyDeviceSettings(doc);
    assert(updateSleepState() && sleepActive && matrix.clears == 1);
    ButtonActions buttons;
    buttons.onBrightnessChange = handleSleepBrightnessChange;
    unsigned savedWrites = nvs.brightnessWrites, sleepWrites = nvs.sleepWrites;
    buttons.handleBrightnessChange(true);
    assert(!updateSleepState() && matrix.brightness == 16);
    assert(renderAsset.resets == 1 && receivedRenderer.resets == 1);
    for (int i = 0; i < 4; ++i) {
        fakeMillis += SLEEP_CHECK_INTERVAL_MS;
        applyDeviceSettings(doc); // An unchanged poll must preserve the override.
        assert(!updateSleepState() && matrix.brightness == 16);
    }
    buttons.handleBrightnessChange(true);
    assert(matrix.brightness == 32);
    for (int i = 0; i < 20; ++i) buttons.handleBrightnessChange(true);
    assert(matrix.brightness == 255);
    for (int i = 0; i < 20; ++i) buttons.handleBrightnessChange(false);
    assert(updateSleepState() && sleepBrightnessOverride == 0);
    assert(matrix.clears == 2 && matrix.shows == 2);
    assert(nvs.brightness == 128 && nvs.brightnessWrites == savedWrites);
    assert(nvs.sleepWrites == sleepWrites && sleepSettings.brightness == 0);
    assert(worker.writes == 0);

    buttons.handleBrightnessChange(true);
    doc.brightness = 192;
    applyDeviceSettings(doc);
    assert(nvs.brightness == 192 && matrix.brightness == 16);
    assert(!updateSleepState() && matrix.brightness == 16);
    // A sleep-settings edit immediately resets the temporary level.
    doc.sleep.brightness = 10;
    applyDeviceSettings(doc);
    assert(!updateSleepState() && matrix.brightness == 10);
    buttons.handleBrightnessChange(true);
    assert(matrix.brightness == 26); // Step from sleep brightness, not saved 192.
    fakeEpoch += 7 * 60 * 60; // 07:30, outside sleep.
    fakeMillis += SLEEP_CHECK_INTERVAL_MS;
    assert(!updateSleepState() && !sleepActive && matrix.brightness == 192);
    assert(sleepBrightnessOverride == -1);
    buttons.handleBrightnessChange(false);
    assert(nvs.brightness == 176 && matrix.brightness == 176 && worker.writes == 1);
    fakeEpoch += 16 * 60 * 60; // Next sleep window, 23:30.
    fakeMillis += SLEEP_CHECK_INTERVAL_MS;
    assert(!updateSleepState() && sleepActive && matrix.brightness == 10);
    buttons.handleBrightnessChange(true);
    doc.sleep.enabled = false;
    applyDeviceSettings(doc);
    assert(!updateSleepState() && matrix.brightness == 176 && !sleepActive);
    doc.sleep.enabled = true;
    doc.sleep.brightness = 0;
    applyDeviceSettings(doc);
    TimeSync::valid = false;
    assert(!updateSleepState() && !sleepActive);
    TimeSync::valid = true;
    fakeMillis += SLEEP_CHECK_INTERVAL_MS;
    assert(updateSleepState());
    // Model a restart: the RAM override initializes to -1.
    buttons.handleBrightnessChange(true);
    sleepBrightnessOverride = -1;
    assert(updateSleepState() && sleepSettings.brightness == 0);
    std::cout << "Sleep brightness runtime tests passed\n";
}
