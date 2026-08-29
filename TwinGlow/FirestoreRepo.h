#ifndef FIRESTORE_REPO_H
#define FIRESTORE_REPO_H

#include "Config.h"
#include <FirebaseClient.h>
#include "FirebaseTypes.h"
#include <Arduino.h>
#include <vector>
#include <ArduinoJson.h>

class FirebaseClientWrap;

// Data structures
struct ScreenConfig {
    String id;
    String type; // CLOCK, IMAGE, ANIMATION, SENSOR
    int order;
    bool enabled;
    int durationMs;
    
    // Shared screen reference
    String pairId;
    String sharedScreenId;
    
    // Asset for IMAGE/ANIMATION (local or from shared defaultAssetId)
    String assetId;
    // Asset shown first; the pool starts here rather than at index 0.
    String defaultAssetId;
    // Current index into availableAssetIds, advanced by the action button
    int currentAssetIndex;
    std::vector<String> availableAssetIds;
    // When false, the action button does not cycle the pool
    bool allowManualSwitch;

    // Config JSON (for CLOCK/SENSOR) - stored as string for simplicity
    String configJson;
};

struct SharedScreenConfig {
    String type;
    String defaultAssetId;
    std::vector<String> availableAssetIds;
    bool allowManualSwitch;
    bool loop; // For animations
};

struct AssetData {
    String id;
    String type; // IMAGE, ANIMATION
    String encoding; // SPARSE_I16_RGB888, DELTA_SPARSE_I16_RGB888
    String pixelsJson; // JSON string for pixels
    String basePixelsJson; // JSON string for base pixels (animations)
    String framesJson; // JSON string for frames (animations)
};

/**
 * Firestore repository
 * Handles all Firestore operations
 */
class FirestoreRepo {
public:
    FirestoreRepo(FirebaseClientWrap* wrap, const String& projectId, const String& deviceId);
    
    // Device operations
    // tzPosix receives the device's POSIX TZ rule, or "" when the doc has no
    // timezone yet (firmware-created docs, or a device the app has never seen).
    bool getDeviceDoc(int& configVersion, bool& bme680Present, String& tzPosix);
    bool createDeviceDoc(const String& fwVersion);
    bool updateDeviceCapability(bool bme680Present);
    
    // Device claiming
    bool claimDevice(const String& uid);
    
    // Screen operations
    bool getScreens(std::vector<ScreenConfig>& screens);
    bool getSharedScreen(const String& pairId, const String& sharedScreenId, SharedScreenConfig& config);
    
    // Asset operations
    bool getAsset(const String& assetId, AssetData& asset);
    
    // Config version polling. The device doc is fetched whole anyway, so the
    // timezone rides along on the existing 60s poll at no extra network cost.
    bool checkConfigVersion(int& version, String& tzPosix);
    
private:
    FirebaseClientWrap* wrap;
    String projectId;
    String deviceId;
    
    String getDevicePath() const;  // "devices/{deviceId}" for Firestore
    String getScreensPath() const;
    String getAssetPath(const String& assetId) const;
    String getSharedScreenPath(const String& pairId, const String& sharedScreenId) const;
    String getUserDevicePath(const String& uid) const;
};

#endif // FIRESTORE_REPO_H
