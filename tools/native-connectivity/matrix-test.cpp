#include "MatrixDriver.h"
#include <cassert>
#include <cmath>
#include <iostream>
unsigned long fakeMillis = 100;
int main() {
    MatrixDriver matrix;
    assert(matrix.begin());
    // Independently determine the physical top-right pixel for each mount.
    const unsigned expectedIndices[] = {15, 240, 255, 0, 255};
    const auto offset = expectedIndices[PANEL_ORIENTATION] * 3;
    auto* strip = Adafruit_NeoPixel::active;
    for (unsigned brightness : {1, 10, 29, 128, 255}) {
        matrix.setBrightness(brightness);
        matrix.fill(0x234567);
        matrix.setPixelOriented(15, 0, 0xEDAB63);
        const std::vector<uint8_t> original(strip->getPixels(), strip->getPixels() + 768);
        for (auto status : {ConnectivityStatus::WifiOffline, ConnectivityStatus::FirebaseUnavailable}) {
            assert(matrix.setConnectivityStatus(status));
            assert(!matrix.setConnectivityStatus(status));
            for (int frame = 0; frame < 50; ++frame) {
                matrix.show();
                auto expected = original;
                auto pwm = [&](unsigned channel) {
                    const auto gamma = unsigned(powf(channel / 255.0f, 2.2f) * 255.0f + 0.5f);
                    return brightness == 255 ? gamma : (gamma * (brightness + 1)) >> 8;
                };
                expected[offset] = status == ConnectivityStatus::WifiOffline ? 0 : pwm(128);
                expected[offset + 1] = pwm(255); expected[offset + 2] = 0;
                assert(Adafruit_NeoPixel::presented == expected);
                assert(std::equal(original.begin(), original.end(), strip->getPixels()));
            }
        }
        matrix.setConnectivityStatus(ConnectivityStatus::Online);
        matrix.show();
        assert(Adafruit_NeoPixel::presented == original);
        matrix.setConnectivityStatus(ConnectivityStatus::WifiOffline, false);
        matrix.show();
        assert(Adafruit_NeoPixel::presented == original); // BLE: disabled.
        matrix.setConnectivityStatus(ConnectivityStatus::WifiOffline);
        matrix.setBrightness(brightness); // Brightness path must also overlay.
        assert(Adafruit_NeoPixel::presented[offset + 1] > 0);
        matrix.clear();
        assert(Adafruit_NeoPixel::presented[offset + 1] > 0);
        matrix.setDisplayBlanked(true);
        matrix.clear();
        matrix.setConnectivityStatus(ConnectivityStatus::FirebaseUnavailable);
        matrix.show();
        assert(std::all_of(Adafruit_NeoPixel::presented.begin(), Adafruit_NeoPixel::presented.end(), [](auto b){return b == 0;}));
        matrix.setDisplayBlanked(false);
        matrix.setConnectivityStatus(ConnectivityStatus::Online);
    }
    std::cout << "Matrix overlay tests passed, orientation=" << PANEL_ORIENTATION << "\n";
}
