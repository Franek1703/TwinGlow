#ifndef FIRESTORE_REPO_H
#define FIRESTORE_REPO_H

#include "PairingConfig.h"
#include <FirebaseClient.h>
// getAsset() pulls documents up to ~10KB. A stock FirebaseClient buffers a
// response body twice over, so one of those needs ~20KB of contiguous heap -
// more than a fragmented ESP32 without PSRAM can supply, and the failure
// surfaces as an empty body with error code 0 rather than an allocation error.
// tools/firebaseclient-patch/ fixes that in the library; this catches a build
// against an unpatched copy, which an Arduino IDE library update produces
// silently.
//
// #error rather than #warning deliberately: the sketch builds with
// `--warnings none`, which suppresses #warning outright, and an unnoticed
// unpatched build fails at runtime as a screen that never loads. Recovery is
// one command.
#if !defined(FIREBASECLIENT_PAYLOAD_MOVE_PATCH) || !defined(FIREBASECLIENT_REQUEST_LINE_PATCH) || !defined(FIREBASECLIENT_DOCUMENT_MASK_COPY_PATCH)
#error "FirebaseClient is missing required TwinGlow patches. Run tools/firebaseclient-patch/apply.sh and rebuild."
#endif
#include "FirebaseTypes.h"
#include "SleepSchedule.h"
#include <Arduino.h>
#include <vector>
#include <ArduinoJson.h>

class FirebaseClientWrap;

#include "FirestoreModels.h"

/**
 * Firestore repository
 * Handles all Firestore operations
 */
class FirestoreRepo {
public:
    FirestoreRepo(FirebaseClientWrap* wrap, const String& projectId, const String& deviceId);
    
    // Device operations
    // Fields the document does not carry are left at the sentinels documented
    // on DeviceDoc, which every caller reads as "keep what you have".
    bool getDeviceDoc(DeviceDoc& out);
    bool createDeviceDoc(const String& fwVersion);
    bool updateDeviceCapability(bool bme680Present);

    // Pushes a brightness set with the physical +/- buttons back up, so the
    // app's slider shows what the panel is actually running at.
    //
    // Patches the single field: bumping configVersion here would make the
    // device's own write look like an owner edit and trigger a full screen and
    // asset reload on the next poll.
    bool updateBrightness(uint8_t brightness);
    
    // Device claiming
    bool claimDevice(const String& uid);
    
    // Screen operations
    bool getScreens(std::vector<ScreenConfig>& screens);
    
    // Asset operations
    bool getAsset(const String& assetId, AssetData& asset, const String& knownRevision = String());
    
    // Config version polling. The device doc is fetched whole anyway, so the
    // timezone, brightness and sleep window ride along on the existing 60s
    // poll at no extra network cost.
    bool checkConfigVersion(DeviceDoc& out);
    
private:
    FirebaseClientWrap* wrap;
    String projectId;
    String deviceId;
    
    String getDevicePath() const;  // "devices/{deviceId}" for Firestore
    String getScreensPath() const;
    String getAssetPath(const String& assetId) const;
    String getUserDevicePath(const String& uid) const;
};

#endif // FIRESTORE_REPO_H
