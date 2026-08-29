#ifndef TIME_SYNC_H
#define TIME_SYNC_H

#include <Arduino.h>
#include "Config.h"
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
    
    time_t getNtpTime();
};

#endif // TIME_SYNC_H
