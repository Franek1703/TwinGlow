#include "FirestoreRepo.h"
#include "Config.h"
#include <ArduinoJson.h>

FirestoreRepo::FirestoreRepo(void* firestoreInstance, const String& projId, const String& devId)
    : firestore(firestoreInstance), projectId(projId), deviceId(devId) {
    if (firestore == nullptr) {
        Serial.println(F("[FirestoreRepo] WARNING: Firestore instance is nullptr"));
        Serial.println(F("[FirestoreRepo] Update FirebaseTypes.h with correct class names"));
    }
}

String FirestoreRepo::getDevicePath() const {
    return "/devices/" + deviceId;
}

String FirestoreRepo::getScreensPath() const {
    return "/devices/" + deviceId + "/screens";
}

String FirestoreRepo::getAssetPath(const String& assetId) const {
    return "/assets/" + assetId;
}

String FirestoreRepo::getSharedScreenPath(const String& pairId, const String& sharedScreenId) const {
    return "/pairs/" + pairId + "/sharedScreens/" + sharedScreenId;
}

String FirestoreRepo::getUserDevicePath(const String& uid) const {
    return "/users/" + uid + "/devices/" + deviceId;
}

bool FirestoreRepo::getDeviceDoc(int& configVersion, bool& bme680Present) {
    if (firestore == nullptr) {
        Serial.println(F("[Firestore] Firestore not initialized - check FirebaseTypes.h"));
        configVersion = 0;
        bme680Present = false;
        return false;
    }
    // TODO: FirebaseClient library uses async API (get(AsyncClientClass&, Parent, path) -> String).
    // Integrate AsyncClient and parse JSON with ArduinoJson to restore Firestore reads.
    configVersion = 0;
    bme680Present = false;
    return false;
}

bool FirestoreRepo::createDeviceDoc(const String& fwVersion) {
    if (firestore == nullptr) return false;
    // TODO: Use FirebaseClient async API (createDocument(AsyncClientClass&, Parent, path, Document<Values::Value>)) with ArduinoJson-built payload.
    (void)fwVersion;
    return false;
}

bool FirestoreRepo::updateDeviceCapability(bool bme680Present) {
    if (firestore == nullptr) return false;
    // TODO: Use FirebaseClient async API for updateDocument with ArduinoJson payload.
    (void)bme680Present;
    return false;
}

bool FirestoreRepo::claimDevice(const String& uid) {
    int configVersion;
    bool bme680Present;
    if (!getDeviceDoc(configVersion, bme680Present)) {
        if (!createDeviceDoc(FW_VERSION)) {
            return false;
        }
    }
    if (firestore == nullptr) return false;
    // TODO: Use FirebaseClient async API to create membership document.
    (void)uid;
    return false;
}

bool FirestoreRepo::getScreens(std::vector<ScreenConfig>& screens) {
    if (firestore == nullptr) return false;
    screens.clear();
    // TODO: Use FirebaseClient async listDocuments and parse with ArduinoJson.
    return false;
}

bool FirestoreRepo::getSharedScreen(const String& pairId, const String& sharedScreenId, SharedScreenConfig& config) {
    if (firestore == nullptr) return false;
    config.type = "";
    config.defaultAssetId = "";
    config.availableAssetIds.clear();
    config.allowManualSwitch = false;
    config.loop = false;
    (void)pairId;
    (void)sharedScreenId;
    // TODO: Use FirebaseClient async get() and parse with ArduinoJson.
    return false;
}

bool FirestoreRepo::getAsset(const String& assetId, AssetData& asset) {
    if (firestore == nullptr) return false;
    asset.id = assetId;
    asset.type = "";
    asset.encoding = "";
    asset.pixelsJson = "";
    asset.basePixelsJson = "";
    asset.framesJson = "";
    // TODO: Use FirebaseClient async get() and parse with ArduinoJson.
    return false;
}

bool FirestoreRepo::checkConfigVersion(int& version) {
    bool dummy;
    return getDeviceDoc(version, dummy); // Reuse getDeviceDoc
}
