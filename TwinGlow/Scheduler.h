#ifndef SCHEDULER_H
#define SCHEDULER_H

#include <Arduino.h>
#include "Config.h"

/**
 * Periodic task scheduler
 * Manages all periodic operations
 */
class Scheduler {
public:
    Scheduler();
    
    void update(); // Call in loop()
    
    // Task registration
    void schedulePresenceUpdate(void (*callback)());
    void scheduleTelemetryUpdate(void (*callback)());
    void scheduleConfigPoll(void (*callback)());
    void scheduleNtpSync(void (*callback)());
    
private:
    unsigned long lastPresenceMs;
    unsigned long lastTelemetryMs;
    unsigned long lastConfigPollMs;
    unsigned long lastNtpSyncMs;
    
    void (*presenceCallback)();
    void (*telemetryCallback)();
    void (*configPollCallback)();
    void (*ntpSyncCallback)();
    
    void checkPresence();
    void checkTelemetry();
    void checkConfigPoll();
    void checkNtpSync();
};

#endif // SCHEDULER_H
