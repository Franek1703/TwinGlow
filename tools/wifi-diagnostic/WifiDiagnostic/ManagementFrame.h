#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace wifi_diagnostic {
enum class Kind { Ignore, Beacon, Auth, Association, Deauth, Disassoc, Protected };
struct Reply {
    Kind kind = Kind::Ignore;
    uint16_t algorithm = 0;
    uint16_t sequence = 0;
    uint16_t code = 0;
};
inline uint16_t little16(const uint8_t* bytes) {
    return uint16_t(bytes[0]) | (uint16_t(bytes[1]) << 8);
}
// len excludes the four-byte FCS. Only inspect our selected AP and frames
// addressed to this station. Never interpret protected/encrypted bodies.
inline Reply inspect(const uint8_t* frame, size_t len,
                     const uint8_t* station, const uint8_t* ap) {
    Reply reply;
    if (!frame || len < 24 || (frame[0] & 0x0f) != 0 || (frame[1] & 3) != 0 ||
        memcmp(frame + 10, ap, 6) != 0 || memcmp(frame + 16, ap, 6) != 0) return reply;
    const unsigned subtype = frame[0] >> 4;
    if (subtype == 8 && len >= 36) {
        reply.kind = Kind::Beacon;
        return reply;
    }
    if (memcmp(frame + 4, station, 6) != 0) return reply;
    if (subtype != 11 && subtype != 1 && subtype != 3 && subtype != 12 && subtype != 10)
        return reply;
    if (frame[1] & 0x40) {
        reply.kind = Kind::Protected;
        return reply;
    }
    if (subtype == 11 && len >= 30) {
        reply.kind = Kind::Auth;
        reply.algorithm = little16(frame + 24);
        reply.sequence = little16(frame + 26);
        reply.code = little16(frame + 28);
    } else if ((subtype == 1 || subtype == 3) && len >= 30) {
        reply.kind = Kind::Association;
        reply.code = little16(frame + 26);
    } else if ((subtype == 12 || subtype == 10) && len >= 26) {
        reply.kind = subtype == 12 ? Kind::Deauth : Kind::Disassoc;
        reply.code = little16(frame + 24);
    }
    return reply;
}
}
