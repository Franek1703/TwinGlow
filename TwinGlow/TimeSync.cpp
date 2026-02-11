#include "TimeSync.h"
#include <time.h>
#include <WiFi.h>
#include <sys/time.h>

TimeSync::TimeSync() : lastSyncMs(0), synced(false) {
}

bool TimeSync::sync(FirebaseApp* app) {
    if (!WiFi.isConnected()) {
        Serial.println(F("[TimeSync] Wi-Fi not connected"));
        return false;
    }
    
    Serial.println(F("[TimeSync] Starting NTP sync..."));
    
    // Use FirebaseClient's NTP helper
    time_t ntpTime = getNtpTime();
    
    if (ntpTime > 0) {
        // Set time for Firebase app
        app->setTime(ntpTime);
        
        // Also set system time
        struct timeval tv;
        tv.tv_sec = ntpTime;
        tv.tv_usec = 0;
        settimeofday(&tv, NULL);
        
        lastSyncMs = millis();
        synced = true;
        
        Serial.print(F("[TimeSync] Sync successful: "));
        Serial.println(ctime(&ntpTime));
        return true;
    } else {
        Serial.println(F("[TimeSync] NTP sync failed (getNtpTime() returned 0)"));
        synced = false;
        return false;
    }
}

bool TimeSync::shouldSync() const {
    if (!synced) return true; // Always sync if never synced
    
    unsigned long elapsed = millis() - lastSyncMs;
    return elapsed >= NTP_SYNC_INTERVAL_MS;
}

time_t TimeSync::getNtpTime() {
    const char* ntpServer = "pool.ntp.org";
    const int timeZone = 0; // UTC

    Serial.print(F("[TimeSync] configTime("));
    Serial.print(timeZone * 3600);
    Serial.print(F(", 0, "));
    Serial.print(ntpServer);
    Serial.println(F(")"));

    configTime(timeZone * 3600, 0, ntpServer);

    time_t now = time(nullptr);
    int retries = 0;
    while (now < 1000000000 && retries < 10) {
        delay(100);
        now = time(nullptr);
        retries++;
        if (retries <= 3 || retries == 10) {
            Serial.print(F("[TimeSync] NTP wait retry "));
            Serial.print(retries);
            Serial.print(F("/10, now="));
            Serial.println(now);
        }
    }

    if (now < 1000000000) {
        Serial.print(F("[TimeSync] NTP failed: time invalid after 10 retries (now="));
        Serial.print(now);
        Serial.println(F(", expected >= 1000000000)"));
        return 0;
    }

    return now;
}
