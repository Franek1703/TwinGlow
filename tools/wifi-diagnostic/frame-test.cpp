#include "WifiDiagnostic/ManagementFrame.h"
#include <array>
#include <cassert>
#include <iostream>
using namespace wifi_diagnostic;
int main() {
    const uint8_t station[6] = {2, 3, 4, 5, 6, 7};
    const uint8_t ap[6] = {8, 9, 10, 11, 12, 13};
    std::array<uint8_t, 40> frame{};
    frame[0] = 0xb0;
    memcpy(frame.data() + 4, station, 6);
    memcpy(frame.data() + 10, ap, 6);
    memcpy(frame.data() + 16, ap, 6);
    frame[26] = 2;
    auto reply = inspect(frame.data(), 30, station, ap);
    assert(reply.kind == Kind::Auth && reply.sequence == 2 && reply.code == 0);
    frame[24] = 3; frame[28] = 76;
    reply = inspect(frame.data(), 30, station, ap);
    assert(reply.algorithm == 3 && reply.code == 76); // SAE status is not a deauth reason.
    for (size_t length = 0; length < 30; ++length) {
        // An exactly sized allocation lets ASan detect reads beyond packet length.
        auto* truncated = new uint8_t[length];
        memcpy(truncated, frame.data(), length);
        assert(inspect(truncated, length, station, ap).kind == Kind::Ignore);
        delete[] truncated;
    }
    assert(inspect(nullptr, 40, station, ap).kind == Kind::Ignore);
    frame[4] ^= 1; assert(inspect(frame.data(), 40, station, ap).kind == Kind::Ignore); frame[4] ^= 1;
    frame[10] ^= 1; assert(inspect(frame.data(), 40, station, ap).kind == Kind::Ignore); frame[10] ^= 1;
    frame[16] ^= 1; assert(inspect(frame.data(), 40, station, ap).kind == Kind::Ignore); frame[16] ^= 1;
    frame[1] = 0x40;
    reply = inspect(frame.data(), 40, station, ap);
    assert(reply.kind == Kind::Protected && reply.code == 0);
    frame[1] = 0;
    frame[0] = 0x10; frame[26] = 17;
    reply = inspect(frame.data(), 30, station, ap);
    assert(reply.kind == Kind::Association && reply.code == 17);
    frame[0] = 0x30;
    assert(inspect(frame.data(), 30, station, ap).kind == Kind::Association);
    frame[0] = 0xc0; frame[24] = 2; frame[25] = 1;
    reply = inspect(frame.data(), 26, station, ap);
    assert(reply.kind == Kind::Deauth && reply.code == 258);
    assert(inspect(frame.data(), 25, station, ap).kind == Kind::Ignore);
    frame[0] = 0xa0;
    assert(inspect(frame.data(), 26, station, ap).kind == Kind::Disassoc);
    frame[0] = 0x80; memset(frame.data() + 4, 255, 6);
    assert(inspect(frame.data(), 36, station, ap).kind == Kind::Beacon);
    assert(inspect(frame.data(), 35, station, ap).kind == Kind::Ignore);
    frame[0] = 0x88; assert(inspect(frame.data(), 40, station, ap).kind == Kind::Ignore); // Data, not management.
    frame[0] = 0xb1; assert(inspect(frame.data(), 40, station, ap).kind == Kind::Ignore); // Unsupported protocol version.
    std::cout << "Management frame tests passed: lengths, addressing, status/reason fields, protected bodies\n";
}
