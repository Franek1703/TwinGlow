#include "Scheduler.h"

Scheduler::Scheduler() 
    : lastPresenceMs(0), lastTelemetryMs(0), lastConfigPollMs(0),
      lastRevisionPollMs(0), lastNtpSyncMs(0),
      presenceCallback(nullptr), telemetryCallback(nullptr),
      configPollCallback(nullptr), revisionPollCallback(nullptr),
      ntpSyncCallback(nullptr) {
}

void Scheduler::update() {
    checkPresence();
    checkTelemetry();
    checkConfigPoll();
    checkRevisionPoll();
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

void Scheduler::scheduleRevisionPoll(void (*callback)()) {
    revisionPollCallback = callback;
    lastRevisionPollMs = millis();
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

void Scheduler::checkRevisionPoll() {
    if (revisionPollCallback == nullptr) return;

    unsigned long now = millis();
    if (now - lastRevisionPollMs >= REVISION_POLL_INTERVAL_MS) {
        revisionPollCallback();
        lastRevisionPollMs = now;
    }
}

void Scheduler::checkNtpSync() {
    if (ntpSyncCallback == nullptr) return;

    // Ticks at the short retry cadence; TimeSync::shouldSync() decides whether
    // an attempt actually happens, holding the 6-hour interval once synced and
    // retrying every NTP_RETRY_INTERVAL_MS while the clock is still unusable.
    unsigned long now = millis();
    if (now - lastNtpSyncMs >= NTP_RETRY_INTERVAL_MS) {
        ntpSyncCallback();
        lastNtpSyncMs = now;
    }
}
