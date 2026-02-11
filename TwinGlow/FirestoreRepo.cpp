#include "FirestoreRepo.h"
#include "FirebaseClientWrap.h"
#include "Config.h"
#include <ArduinoJson.h>

#if !defined(ENABLE_FIRESTORE)
// Stubs when Firestore not enabled
FirestoreRepo::FirestoreRepo(FirebaseClientWrap* wrap, const String& projId, const String& devId)
    : wrap(wrap), projectId(projId), deviceId(devId) {
}
String FirestoreRepo::getDevicePath() const { return ""; }
String FirestoreRepo::getScreensPath() const { return ""; }
String FirestoreRepo::getAssetPath(const String&) const { return ""; }
String FirestoreRepo::getSharedScreenPath(const String&, const String&) const { return ""; }
String FirestoreRepo::getUserDevicePath(const String&) const { return ""; }
bool FirestoreRepo::getDeviceDoc(int& v, bool& b) { v = 0; b = false; return false; }
bool FirestoreRepo::createDeviceDoc(const String&) { return false; }
bool FirestoreRepo::updateDeviceCapability(bool) { return false; }
bool FirestoreRepo::claimDevice(const String&) { return false; }
bool FirestoreRepo::getScreens(std::vector<ScreenConfig>&) { return false; }
bool FirestoreRepo::getSharedScreen(const String&, const String&, SharedScreenConfig&) { return false; }
bool FirestoreRepo::getAsset(const String&, AssetData&) { return false; }
bool FirestoreRepo::checkConfigVersion(int& version) { bool d; return getDeviceDoc(version, d); }
#else

FirestoreRepo::FirestoreRepo(FirebaseClientWrap* wrap, const String& projId, const String& devId)
    : wrap(wrap), projectId(projId), deviceId(devId) {
    if (wrap == nullptr || wrap->getFirestore() == nullptr) {
        Serial.println(F("[FirestoreRepo] WARNING: wrap or Firestore is null"));
    }
}

String FirestoreRepo::getDevicePath() const {
    return "devices/" + deviceId;
}

String FirestoreRepo::getScreensPath() const {
    return "devices/" + deviceId + "/screens";
}

String FirestoreRepo::getAssetPath(const String& assetId) const {
    return "assets/" + assetId;
}

String FirestoreRepo::getSharedScreenPath(const String& pairId, const String& sharedScreenId) const {
    return "pairs/" + pairId + "/sharedScreens/" + sharedScreenId;
}

String FirestoreRepo::getUserDevicePath(const String& uid) const {
    return "users/" + uid + "/devices/" + deviceId;
}

// Helper: get string from Firestore field object (e.g. {"stringValue": "x"})
static bool firestoreFieldToString(const JsonObject& field, String& out) {
    if (field.containsKey("stringValue")) {
        out = field["stringValue"].as<String>();
        return true;
    }
    if (field.containsKey("integerValue")) {
        out = field["integerValue"].as<String>();
        return true;
    }
    return false;
}

static bool firestoreFieldToInt(const JsonObject& field, int& out) {
    if (field.containsKey("integerValue")) {
        out = field["integerValue"].as<int>();
        return true;
    }
    return false;
}

static bool firestoreFieldToBool(const JsonObject& field, bool& out) {
    if (field.containsKey("booleanValue")) {
        out = field["booleanValue"].as<bool>();
        return true;
    }
    return false;
}

bool FirestoreRepo::getDeviceDoc(int& configVersion, bool& bme680Present) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    Firestore::Parent parent(projectId, "");
    DocumentMask mask;
    GetDocumentOptions options(mask);
    String path = getDevicePath();
    String response = documents->get(*aClient, parent, path, options);
    if (aClient->lastError().code() != 0) {
        Serial.print(F("[Claiming] getDeviceDoc GET failed, code="));
        Serial.print(aClient->lastError().code());
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        configVersion = 0;
        bme680Present = false;
        return false;
    }

    DynamicJsonDocument doc(2048);
    if (deserializeJson(doc, response) != DeserializationError::Ok) {
        Serial.println(F("[Claiming] getDeviceDoc parse failed"));
        configVersion = 0;
        bme680Present = false;
        return false;
    }
    if (!doc.containsKey("fields")) {
        Serial.println(F("[Claiming] getDeviceDoc response missing 'fields'"));
        configVersion = 0;
        bme680Present = false;
        return false;
    }

    JsonObject fields = doc["fields"].as<JsonObject>();
    configVersion = 0;
    if (fields.containsKey("configVersion")) {
        firestoreFieldToInt(fields["configVersion"].as<JsonObject>(), configVersion);
    }
    bme680Present = false;
    if (fields.containsKey("hw")) {
        JsonObject hw = fields["hw"].as<JsonObject>();
        if (hw.containsKey("mapValue") && hw["mapValue"].containsKey("fields")) {
            JsonObject hwFields = hw["mapValue"]["fields"].as<JsonObject>();
            if (hwFields.containsKey("bme680")) {
                firestoreFieldToBool(hwFields["bme680"].as<JsonObject>(), bme680Present);
            }
        }
    }
    return true;
}

bool FirestoreRepo::createDeviceDoc(const String& fwVersion) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    Firestore::Parent parent(projectId, "");
    DocumentMask mask;
    Document<Values::Value> doc;
    doc.add("fwVersion", Values::Value(Values::StringValue(fwVersion)));
    doc.add("configVersion", Values::Value(Values::IntegerValue(0)));
    Values::MapValue hw;
    hw.add("bme680", Values::BooleanValue(false));
    doc.add("hw", Values::Value(hw));

    String path = getDevicePath();
    documents->createDocument(*aClient, parent, path, mask, doc);
    if (aClient->lastError().code() != 0) {
        Serial.print(F("[Claiming] createDeviceDoc failed, code="));
        Serial.print(aClient->lastError().code());
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    return true;
}

bool FirestoreRepo::updateDeviceCapability(bool bme680Present) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    Firestore::Parent parent(projectId, "");
    DocumentMask updateMask("hw.bme680");
    DocumentMask mask;
    Precondition precondition;
    PatchDocumentOptions patchOptions(updateMask, mask, precondition);
    Document<Values::Value> doc;
    Values::MapValue hw;
    hw.add("bme680", Values::BooleanValue(bme680Present));
    doc.add("hw", Values::Value(hw));

    String path = getDevicePath();
    documents->patch(*aClient, parent, path, patchOptions, doc);
    return aClient->lastError().code() == 0;
}

bool FirestoreRepo::claimDevice(const String& uid) {
    if (wrap == nullptr || uid.length() == 0) {
        Serial.println(F("[Claiming] claimDevice: wrap null or uid empty"));
        return false;
    }
    Serial.print(F("[Claiming] Ensuring device doc exists..."));
    int cv;
    bool bme;
    if (!getDeviceDoc(cv, bme)) {
        Serial.println(F(" getDeviceDoc failed, creating device doc"));
        if (!createDeviceDoc(FW_VERSION)) {
            Serial.println(F("[Claiming] createDeviceDoc failed"));
            return false;
        }
        Serial.println(F("[Claiming] createDeviceDoc ok"));
    } else {
        Serial.print(F(" ok (configVersion="));
        Serial.print(cv);
        Serial.println(F(")"));
    }

    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) {
        Serial.println(F("[Claiming] documents or aClient null"));
        return false;
    }

    Firestore::Parent parent(projectId, "");
    DocumentMask mask;
    Document<Values::Value> doc;
    doc.add("role", Values::Value(Values::StringValue("OWNER")));

    String path = getUserDevicePath(uid);
    Serial.print(F("[Claiming] createDocument: "));
    Serial.println(path);
    documents->createDocument(*aClient, parent, path, mask, doc);
    int errCode = aClient->lastError().code();
    if (errCode != 0) {
        Serial.print(F("[Claiming] createDocument failed, code="));
        Serial.print(errCode);
        Serial.print(F(" message="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    Serial.println(F("[Claiming] createDocument ok"));
    return true;
}

bool FirestoreRepo::getScreens(std::vector<ScreenConfig>& screens) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    Firestore::Parent parent(projectId, "");
    ListDocumentsOptions listOpts;
    String listPath = getScreensPath();
    String response = documents->list(*aClient, parent, listPath, listOpts);
    if (aClient->lastError().code() != 0) return false;

    DynamicJsonDocument doc(8192);
    if (deserializeJson(doc, response) != DeserializationError::Ok) return false;
    if (!doc.containsKey("documents")) {
        screens.clear();
        return true;
    }

    screens.clear();
    JsonArray arr = doc["documents"].as<JsonArray>();
    for (JsonVariant docVar : arr) {
        JsonObject docObj = docVar.as<JsonObject>();
        ScreenConfig sc;
        sc.id = "";
        sc.type = "";
        sc.order = 0;
        sc.enabled = true;
        sc.durationMs = 5000;
        sc.pairId = "";
        sc.sharedScreenId = "";
        sc.assetId = "";
        sc.currentAssetIndex = 0;
        sc.configJson = "";
        if (!docObj.containsKey("name") || !docObj.containsKey("fields")) continue;
        String name = docObj["name"].as<String>();
        int lastSlash = name.lastIndexOf('/');
        if (lastSlash >= 0) sc.id = name.substring(lastSlash + 1);
        JsonObject fields = docObj["fields"].as<JsonObject>();
        if (fields.containsKey("type")) firestoreFieldToString(fields["type"].as<JsonObject>(), sc.type);
        if (fields.containsKey("order")) firestoreFieldToInt(fields["order"].as<JsonObject>(), sc.order);
        if (fields.containsKey("enabled")) firestoreFieldToBool(fields["enabled"].as<JsonObject>(), sc.enabled);
        if (fields.containsKey("durationMs")) { int d; firestoreFieldToInt(fields["durationMs"].as<JsonObject>(), d); sc.durationMs = d; }
        if (fields.containsKey("pairId")) firestoreFieldToString(fields["pairId"].as<JsonObject>(), sc.pairId);
        if (fields.containsKey("sharedScreenId")) firestoreFieldToString(fields["sharedScreenId"].as<JsonObject>(), sc.sharedScreenId);
        if (fields.containsKey("assetId")) firestoreFieldToString(fields["assetId"].as<JsonObject>(), sc.assetId);
        screens.push_back(sc);
    }
    // Sort by order
    for (size_t i = 0; i < screens.size(); i++) {
        for (size_t j = i + 1; j < screens.size(); j++) {
            if (screens[j].order < screens[i].order) {
                ScreenConfig tmp = screens[i];
                screens[i] = screens[j];
                screens[j] = tmp;
            }
        }
    }
    return true;
}

bool FirestoreRepo::getSharedScreen(const String& pairId, const String& sharedScreenId, SharedScreenConfig& config) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    config.type = "";
    config.defaultAssetId = "";
    config.availableAssetIds.clear();
    config.allowManualSwitch = false;
    config.loop = false;

    Firestore::Parent parent(projectId, "");
    DocumentMask mask;
    GetDocumentOptions options(mask);
    String path = getSharedScreenPath(pairId, sharedScreenId);
    String response = documents->get(*aClient, parent, path, options);
    if (aClient->lastError().code() != 0) return false;

    DynamicJsonDocument doc(2048);
    if (deserializeJson(doc, response) != DeserializationError::Ok) return false;
    if (!doc.containsKey("fields")) return false;

    JsonObject fields = doc["fields"].as<JsonObject>();
    if (fields.containsKey("type")) firestoreFieldToString(fields["type"].as<JsonObject>(), config.type);
    if (fields.containsKey("defaultAssetId")) firestoreFieldToString(fields["defaultAssetId"].as<JsonObject>(), config.defaultAssetId);
    if (fields.containsKey("allowManualSwitch")) firestoreFieldToBool(fields["allowManualSwitch"].as<JsonObject>(), config.allowManualSwitch);
    if (fields.containsKey("loop")) firestoreFieldToBool(fields["loop"].as<JsonObject>(), config.loop);
    if (fields.containsKey("availableAssetIds") && fields["availableAssetIds"].containsKey("arrayValue")) {
        JsonArray arr = fields["availableAssetIds"]["arrayValue"]["values"].as<JsonArray>();
        for (JsonObject v : arr) {
            if (v.containsKey("stringValue")) {
                config.availableAssetIds.push_back(v["stringValue"].as<String>());
            }
        }
    }
    return true;
}

// Convert Firestore arrayValue of [index,color] pairs to flat JSON array for AssetCache::parseAsset
static void appendFirestorePixelArray(JsonArray& out, JsonVariant firestoreArr) {
    if (!firestoreArr.containsKey("arrayValue") || !firestoreArr["arrayValue"].containsKey("values")) return;
    JsonArray values = firestoreArr["arrayValue"]["values"].as<JsonArray>();
    for (JsonVariant v : values) {
        if (!v.containsKey("arrayValue") || !v["arrayValue"].containsKey("values")) continue;
        JsonArray pair = v["arrayValue"]["values"].as<JsonArray>();
        if (pair.size() >= 2) {
            JsonArray row = out.add<JsonArray>();
            row.add(pair[0].as<int>());
            row.add(pair[1].as<uint32_t>());
        }
    }
}

bool FirestoreRepo::getAsset(const String& assetId, AssetData& asset) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    asset.id = assetId;
    asset.type = "";
    asset.encoding = "";
    asset.pixelsJson = "";
    asset.basePixelsJson = "";
    asset.framesJson = "";

    Firestore::Parent parent(projectId, "");
    DocumentMask mask;
    GetDocumentOptions options(mask);
    String path = getAssetPath(assetId);
    String response = documents->get(*aClient, parent, path, options);
    if (aClient->lastError().code() != 0) return false;

    DynamicJsonDocument doc(8192);
    if (deserializeJson(doc, response) != DeserializationError::Ok) return false;
    if (!doc.containsKey("fields")) return false;

    JsonObject fields = doc["fields"].as<JsonObject>();
    if (fields.containsKey("type")) firestoreFieldToString(fields["type"].as<JsonObject>(), asset.type);
    if (fields.containsKey("encoding")) firestoreFieldToString(fields["encoding"].as<JsonObject>(), asset.encoding);

    DynamicJsonDocument flat(8192);
    flat["type"] = asset.type;
    flat["encoding"] = asset.encoding;
    if (fields.containsKey("pixels")) {
        JsonArray pixels = flat.createNestedArray("pixels");
        appendFirestorePixelArray(pixels, fields["pixels"]);
    }
    if (fields.containsKey("basePixels")) {
        JsonArray basePixels = flat.createNestedArray("basePixels");
        appendFirestorePixelArray(basePixels, fields["basePixels"]);
    }
    if (fields.containsKey("frames")) {
        JsonArray frames = flat.createNestedArray("frames");
        JsonArray firestoreFrames = fields["frames"]["arrayValue"]["values"].as<JsonArray>();
        for (JsonVariant fv : firestoreFrames) {
            JsonObject frameObj = frames.add<JsonObject>();
            if (fv.containsKey("mapValue") && fv["mapValue"].containsKey("fields")) {
                JsonObject ffields = fv["mapValue"]["fields"].as<JsonObject>();
                if (ffields.containsKey("delayMs")) {
                    int d; firestoreFieldToInt(ffields["delayMs"].as<JsonObject>(), d);
                    frameObj["delayMs"] = d;
                }
                if (ffields.containsKey("pixels")) {
                    JsonArray px = frameObj.createNestedArray("pixels");
                    appendFirestorePixelArray(px, ffields["pixels"]);
                }
            }
        }
    }
    if (fields.containsKey("loop")) {
        bool l; firestoreFieldToBool(fields["loop"].as<JsonObject>(), l);
        flat["loop"] = l;
    }
    serializeJson(flat, asset.pixelsJson);
    return true;
}

bool FirestoreRepo::checkConfigVersion(int& version) {
    bool dummy;
    return getDeviceDoc(version, dummy);
}

#endif // ENABLE_FIRESTORE
