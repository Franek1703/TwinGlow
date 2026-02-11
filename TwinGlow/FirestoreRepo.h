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
    // For shared screens with allowManualSwitch: current index into availableAssetIds
    int currentAssetIndex;
    std::vector<String> availableAssetIds;
    
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
    bool getDeviceDoc(int& configVersion, bool& bme680Present);
    bool createDeviceDoc(const String& fwVersion);
    bool updateDeviceCapability(bool bme680Present);
    
    // Device claiming
    bool claimDevice(const String& uid);
    
    // Screen operations
    bool getScreens(std::vector<ScreenConfig>& screens);
    bool getSharedScreen(const String& pairId, const String& sharedScreenId, SharedScreenConfig& config);
    
    // Asset operations
    bool getAsset(const String& assetId, AssetData& asset);
    
    // Config version polling
    bool checkConfigVersion(int& version);
    
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
