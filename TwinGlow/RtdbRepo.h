#ifndef RTDB_REPO_H
#define RTDB_REPO_H

#include "Config.h"
#include <FirebaseClient.h>
#include "FirebaseTypes.h"
#include <Arduino.h>

/**
 * Realtime Database repository
 * Handles presence, telemetry, and commands
 */
class RtdbRepo {
public:
    RtdbRepo(void* rtdbInstance, const String& deviceId);
    
    // Presence
    bool updatePresence(bool online);
    
    // Telemetry (BME680)
    bool pushTelemetry(float temperature, float humidity, float pressure, float gas);
    
    // Commands
    bool checkCommands(); // Poll for new commands
    bool acknowledgeCommand(const String& commandId, bool success);
    
    // Send to pair event
    bool sendToPair(const String& pairId, const String& screenId, const String& assetId);
    
private:
    void* rtdb; // RTDB instance (FirebaseRTDBType*)
    String deviceId;
    
    // Helper to get RTDB instance with correct type
    FirebaseRTDBType* getRTDB() {
        return static_cast<FirebaseRTDBType*>(rtdb);
    }
    
    String getPresencePath() const;
    String getTelemetryPath() const;
    String getCommandsPath() const;
};

#endif // RTDB_REPO_H
