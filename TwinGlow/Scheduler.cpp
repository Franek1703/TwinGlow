#include "Scheduler.h"

Scheduler::Scheduler() 
    : lastPresenceMs(0), lastTelemetryMs(0), lastConfigPollMs(0), lastNtpSyncMs(0),
      presenceCallback(nullptr), telemetryCallback(nullptr),
      configPollCallback(nullptr), ntpSyncCallback(nullptr) {
}

void Scheduler::update() {
    checkPresence();
    checkTelemetry();
    checkConfigPoll();
    checkNtpSync();
}

void Scheduler::schedulePresenceUpdate(void (*callback)()) {
    presenceCallback = callback;
    lastPresenceMs = millis();
}

void Scheduler::scheduleTelemetryUpdate(void (*callback)()) {
    telemetryCallback = callback;
    lastTelemetryMs = millis();
}

void Scheduler::scheduleConfigPoll(void (*callback)()) {
    configPollCallback = callback;
    lastConfigPollMs = millis();
}

void Scheduler::scheduleNtpSync(void (*callback)()) {
    ntpSyncCallback = callback;
    lastNtpSyncMs = millis();
}

void Scheduler::checkPresence() {
    if (presenceCallback == nullptr) return;
    
    unsigned long now = millis();
    if (now - lastPresenceMs >= PRESENCE_UPDATE_INTERVAL_MS) {
        presenceCallback();
        lastPresenceMs = now;
    }
}

void Scheduler::checkTelemetry() {
    if (telemetryCallback == nullptr) return;
    
    unsigned long now = millis();
    if (now - lastTelemetryMs >= TELEMETRY_UPDATE_INTERVAL_MS) {
        telemetryCallback();
        lastTelemetryMs = now;
    }
}

void Scheduler::checkConfigPoll() {
    if (configPollCallback == nullptr) return;
    
    unsigned long now = millis();
    if (now - lastConfigPollMs >= CONFIG_POLL_INTERVAL_MS) {
        configPollCallback();
        lastConfigPollMs = now;
    }
}

void Scheduler::checkNtpSync() {
    if (ntpSyncCallback == nullptr) return;
    
    unsigned long now = millis();
    if (now - lastNtpSyncMs >= NTP_SYNC_INTERVAL_MS) {
        ntpSyncCallback();
        lastNtpSyncMs = now;
    }
}
