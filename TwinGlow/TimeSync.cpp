#include "TimeSync.h"
#include <time.h>
#include <WiFi.h>
#include <sys/time.h>

// Any epoch below this is the ESP32's power-on default, not a real date.
// 1000000000 = 2001-09-09.
static const time_t TIME_VALID_EPOCH_MIN = 1000000000;

TimeSync::TimeSync() : lastSyncMs(0), synced(false), tzPosix(DEFAULT_TZ_POSIX) {
}

void TimeSync::setTimeZone(const String& posixTz) {
    if (posixTz.length() == 0) return;
    tzPosix = posixTz;
    // setenv+tzset takes effect immediately, so a screen already on the panel
    // picks up the new zone without waiting for the next NTP sync.
    setenv("TZ", tzPosix.c_str(), 1);
    tzset();
    Serial.print(F("[TimeSync] Timezone applied: "));
    Serial.println(tzPosix);
}

bool TimeSync::isTimeValid() {
    return time(nullptr) >= TIME_VALID_EPOCH_MIN;
}

bool TimeSync::sync(FirebaseApp* app) {
    if (!WiFi.isConnected()) {
        Serial.println(F("[TimeSync] Wi-Fi not connected"));
        return false;
    }
    
    Serial.println(F("[TimeSync] Starting NTP sync..."));
    
    // Use FirebaseClient's NTP helper
    time_t ntpTime = getNtpTime();
    
    // Marks the last *attempt*, success or not, so shouldSync() can back off
    // between failed retries instead of hammering NTP every scheduler tick.
    lastSyncMs = millis();

    if (ntpTime > 0) {
        // Set time for Firebase app
        if (app != nullptr) {
            app->setTime(ntpTime);
        }

        // Also set system time
        struct timeval tv;
        tv.tv_sec = ntpTime;
        tv.tv_usec = 0;
        settimeofday(&tv, NULL);

        synced = true;

        Serial.print(F("[TimeSync] Sync successful: "));
        Serial.println(ctime(&ntpTime));
        return true;
    } else {
        Serial.print(F("[TimeSync] NTP sync failed, next retry in "));
        Serial.print(NTP_RETRY_INTERVAL_MS / 1000);
        Serial.println(F("s"));
        synced = false;
        return false;
    }
}

bool TimeSync::shouldSync() const {
    // Retry often while the clock is unusable, then settle into the slow cadence.
    unsigned long interval = synced ? NTP_SYNC_INTERVAL_MS : NTP_RETRY_INTERVAL_MS;
    if (!synced && lastSyncMs == 0) return true; // Never attempted
    return (millis() - lastSyncMs) >= interval;
}

time_t TimeSync::getNtpTime() {
    // configTzTime, not configTime: the latter derives TZ from its two offset
    // arguments and overwrites whatever setTimeZone() installed. Since this runs
    // again every TIME_SYNC_RECONFIG_INTERVAL_MS while waiting and every
    // NTP_SYNC_INTERVAL_MS thereafter, configTime would wipe the zone within
    // seconds of it being applied.
    // Three servers: it falls back in order if the first is unreachable.
    Serial.print(F("[TimeSync] configTzTime("));
    Serial.print(tzPosix);
    Serial.print(F(", pool.ntp.org, time.google.com, time.cloudflare.com), waiting up to "));
    Serial.print(NTP_WAIT_MS);
    Serial.println(F("ms"));

    configTzTime(tzPosix.c_str(), "pool.ntp.org", "time.google.com", "time.cloudflare.com");

    // A cold DNS lookup plus an NTP round trip routinely takes several seconds,
    // so this waits NTP_WAIT_MS rather than the 1s the old retry count allowed.
    unsigned long startMs = millis();
    unsigned long lastLogMs = 0;
    while (!isTimeValid()) {
        if (millis() - startMs >= NTP_WAIT_MS) {
            Serial.print(F("[TimeSync] NTP failed: no valid time after "));
            Serial.print(millis() - startMs);
            Serial.println(F("ms"));
            return 0;
        }
        if (millis() - lastLogMs >= 2000) {
            lastLogMs = millis();
            Serial.print(F("[TimeSync] waiting for NTP... "));
            Serial.print(millis() - startMs);
            Serial.println(F("ms"));
        }
        delay(50);
    }

    time_t now = time(nullptr);
    Serial.print(F("[TimeSync] NTP responded after "));
    Serial.print(millis() - startMs);
    Serial.println(F("ms"));
    return now;
}
