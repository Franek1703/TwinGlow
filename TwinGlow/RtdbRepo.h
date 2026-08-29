#ifndef RTDB_REPO_H
#define RTDB_REPO_H

#include "Config.h"
#include <FirebaseClient.h>
#include "FirebaseTypes.h"
#include <Arduino.h>

class FirebaseClientWrap;

/**
 * Realtime Database repository
 * Handles presence, telemetry, and commands
 */
class RtdbRepo {
public:
    RtdbRepo(FirebaseClientWrap* wrap, const String& deviceId);
    
    // Presence
    bool updatePresence(bool online);
    
    // Telemetry (BME680)
    bool pushTelemetry(float temperature, float humidity, float pressure, float gas);
    
    // Config revision "doorbell" - a single integer the app ticks on every
    // config change. The value itself is meaningless to the device; only the
    // fact that it moved matters, which is what makes it safe to compare
    // against a locally remembered copy without agreeing with Firestore's
    // own configVersion.
    bool getConfigRevision(int& revision);

    // Commands
    bool checkCommands(); // Poll for new commands
    bool acknowledgeCommand(const String& commandId, bool success);
    
    // Send to pair event
    bool sendToPair(const String& pairId, const String& screenId, const String& assetId);
    
private:
    FirebaseClientWrap* wrap;
    String deviceId;
    
    String getPresencePath() const;
    String getTelemetryPath() const;
    String getCommandsPath() const;
    String getConfigPath() const;
    String getPairEventsPath(const String& pairId) const;
};

#endif // RTDB_REPO_H
