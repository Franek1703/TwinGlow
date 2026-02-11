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
        Serial.println(F("[TimeSync] NTP sync failed"));
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
    // Use FirebaseClient's built-in NTP helper
    // This is a simplified version - FirebaseClient has get_ntp_time() helper
    const char* ntpServer = "pool.ntp.org";
    const int timeZone = 0; // UTC
    
    configTime(timeZone * 3600, 0, ntpServer);
    
    time_t now = time(nullptr);
    int retries = 0;
    while (now < 1000000000 && retries < 10) {
        delay(100);
        now = time(nullptr);
        retries++;
    }
    
    if (now < 1000000000) {
        return 0; // Failed
    }
    
    return now;
}
