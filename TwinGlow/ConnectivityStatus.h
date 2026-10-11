#pragma once
#include <stdint.h>

enum class ConnectivityStatus : uint8_t { Online, WifiOffline, FirebaseUnavailable };
enum class CloudService : uint8_t { Rtdb, Firestore };

// Caller supplies synchronization. No network probes, heap allocations or
// changes to playback state are needed to evaluate display connectivity.
class ConnectionHealth {
public:
    void setAuthReady(bool ready) { authReady = ready; }
    void resetConfirmation() { healthy[0] = healthy[1] = false; }
    void record(CloudService service, bool success, int code, uint32_t now) {
        const auto index = static_cast<uint8_t>(service);
        if (success) {
            healthy[index] = true;
            lastSuccessMs = now;
            hasSuccess = true;
        } else if (code < 0 || code == 401 || code == 403 || code == 408 ||
                   code == 429 || code >= 500) {
            healthy[index] = false;
        }
        // Missing/malformed content and local allocation failures do not
        // establish a new communication fault or clear an existing one.
    }
    ConnectivityStatus status(bool wifiConnected, uint32_t now, bool stuck = false) const {
        if (!wifiConnected) return ConnectivityStatus::WifiOffline;
        if (!authReady || !healthy[0] || !healthy[1] || !hasSuccess || stuck ||
            uint32_t(now - lastSuccessMs) >= 60000) {
            return ConnectivityStatus::FirebaseUnavailable;
        }
        return ConnectivityStatus::Online;
    }
private:
    bool healthy[2] = {false, false};
    bool authReady = false;
    bool hasSuccess = false;
    uint32_t lastSuccessMs = 0;
};
