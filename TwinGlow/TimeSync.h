#ifndef TIME_SYNC_H
#define TIME_SYNC_H

#include <Arduino.h>
#include "PairingConfig.h"
#include <FirebaseClient.h>

/**
 * NTP time synchronization
 * Syncs time on boot and every 6 hours
 */
class TimeSync {
public:
    TimeSync();
    
    bool sync(FirebaseApp* app);
    bool shouldSync() const;

    // Applies a POSIX TZ rule (e.g. "CET-1CEST,M3.5.0,M10.5.0/3") so localtime()
    // returns the owner's wall-clock time instead of UTC. Empty strings are
    // ignored; safe to call repeatedly. The rule is also handed to configTzTime()
    // on every re-sync, which is what keeps it from being overwritten.
    void setTimeZone(const String& posixTz);
    const String& getTimeZone() const { return tzPosix; }

    // True once the system clock holds a plausible wall-clock time.
    // The ESP32 SNTP client keeps running in the background, so the clock can
    // become valid after sync() has already returned false - this, not sync()'s
    // return value, is the authoritative check.
    static bool isTimeValid();

    unsigned long getLastSyncMs() const { return lastSyncMs; }
    bool isSynced() const { return synced; }
    
    void setSynced(bool s) { synced = s; }
    
private:
    unsigned long lastSyncMs;
    bool synced;
    String tzPosix;

    time_t getNtpTime();
};

#endif // TIME_SYNC_H
