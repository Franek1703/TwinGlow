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
    if (aClient->lastError().code() != 0) {
        Serial.print(F("[Firestore] getScreens list error: "));
        Serial.println(aClient->lastError().code());
        return false;
    }

    DynamicJsonDocument doc(8192);
    if (deserializeJson(doc, response) != DeserializationError::Ok) {
        Serial.println(F("[Firestore] getScreens: JSON parse error"));
        return false;
    }
    if (!doc.containsKey("documents")) {
        screens.clear();
        Serial.println(F("[Firestore] getScreens: no 'documents' in response"));
        return true;
    }

    screens.clear();
    JsonArray arr = doc["documents"].as<JsonArray>();
    Serial.print(F("[Firestore] getScreens: path="));
    Serial.print(listPath);
    Serial.print(F(" rawDocs="));
    Serial.println(arr.size());
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
        if (fields.containsKey("type")) {
            firestoreFieldToString(fields["type"].as<JsonObject>(), sc.type);
            // Normalize to uppercase for consistent comparison
            sc.type.toUpperCase();
        }
        if (fields.containsKey("order")) firestoreFieldToInt(fields["order"].as<JsonObject>(), sc.order);
        if (fields.containsKey("enabled")) firestoreFieldToBool(fields["enabled"].as<JsonObject>(), sc.enabled);
        if (fields.containsKey("durationMs")) { int d; firestoreFieldToInt(fields["durationMs"].as<JsonObject>(), d); sc.durationMs = d; }
        if (fields.containsKey("pairId")) firestoreFieldToString(fields["pairId"].as<JsonObject>(), sc.pairId);
        if (fields.containsKey("sharedScreenId")) firestoreFieldToString(fields["sharedScreenId"].as<JsonObject>(), sc.sharedScreenId);
        if (fields.containsKey("assetId")) firestoreFieldToString(fields["assetId"].as<JsonObject>(), sc.assetId);
        // Load config JSON for CLOCK/SENSOR screens
        if (fields.containsKey("config")) {
            // Firestore stores nested objects as mapValue with fields
            JsonObject configField = fields["config"].as<JsonObject>();
            if (configField.containsKey("mapValue") && configField["mapValue"].containsKey("fields")) {
                JsonObject configFields = configField["mapValue"]["fields"].as<JsonObject>();
                DynamicJsonDocument configDoc(2048);
                // Convert Firestore mapValue fields to flat JSON
                JsonObject configObj = configDoc.to<JsonObject>();
                // Copy all fields from Firestore format to JSON format
                for (JsonPair kv : configFields) {
                    String key = kv.key().c_str();
                    JsonObject fieldObj = kv.value().as<JsonObject>();
                    if (fieldObj.containsKey("booleanValue")) {
                        configObj[key] = fieldObj["booleanValue"].as<bool>();
                    } else if (fieldObj.containsKey("integerValue")) {
                        configObj[key] = fieldObj["integerValue"].as<uint32_t>();
                    } else if (fieldObj.containsKey("stringValue")) {
                        configObj[key] = fieldObj["stringValue"].as<String>();
                    }
                }
                serializeJson(configDoc, sc.configJson);
            }
        }
        screens.push_back(sc);
    }
    Serial.print(F("[Firestore] getScreens: parsed "));
    Serial.print(screens.size());
    Serial.println(F(" screens"));
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

// Convert Firestore arrayValue of {color, index} objects to flat JSON array for AssetCache::parseAsset
// Format: [{color: 55807, index: 71}, {color: 55807, index: 73}]
static void appendFirestorePixelArray(JsonArray& out, JsonVariant firestoreArr) {
    if (!firestoreArr.containsKey("arrayValue") || !firestoreArr["arrayValue"].containsKey("values")) {
        Serial.println(F("[Firestore] appendFirestorePixelArray: no arrayValue/values"));
        return;
    }
    JsonArray values = firestoreArr["arrayValue"]["values"].as<JsonArray>();
    Serial.print(F("[Firestore] appendFirestorePixelArray: processing "));
    Serial.print(values.size());
    Serial.println(F(" pixel objects"));
    for (JsonVariant v : values) {
        // Check if it's a mapValue (object format: {color: X, index: Y})
        if (v.containsKey("mapValue") && v["mapValue"].containsKey("fields")) {
            JsonObject fields = v["mapValue"]["fields"].as<JsonObject>();
            int index = -1;
            uint32_t color = 0;
            
            if (fields.containsKey("index")) {
                int idx;
                if (firestoreFieldToInt(fields["index"].as<JsonObject>(), idx)) {
                    index = idx;
                }
            }
            if (fields.containsKey("color")) {
                // Color is stored as integerValue in Firestore
                JsonObject colorField = fields["color"].as<JsonObject>();
                if (colorField.containsKey("integerValue")) {
                    color = colorField["integerValue"].as<uint32_t>();
                } else if (colorField.containsKey("stringValue")) {
                    // Fallback for string representation
                    color = strtoul(colorField["stringValue"].as<const char*>(), nullptr, 10);
                }
            }
            
            if (index >= 0) {
                JsonArray row = out.add<JsonArray>();
                row.add(index);
                row.add(color);
            }
        }
        // Legacy support: array format [[index, color], ...]
        else if (v.containsKey("arrayValue") && v["arrayValue"].containsKey("values")) {
            JsonArray pair = v["arrayValue"]["values"].as<JsonArray>();
            if (pair.size() >= 2) {
                JsonArray row = out.add<JsonArray>();
                row.add(pair[0].as<int>());
                row.add(pair[1].as<uint32_t>());
            }
        }
    }
}

bool FirestoreRepo::getAsset(const String& assetId, AssetData& asset) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) {
        Serial.println(F("[Firestore] getAsset: documents or aClient is null"));
        return false;
    }

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
    Serial.print(F("[Firestore] getAsset: querying path="));
    Serial.print(path);
    Serial.print(F(" projectId="));
    Serial.println(projectId);
    
    // Call get() - exact same pattern as getDeviceDoc which works
    // Note: FirebaseClient get() is synchronous and blocks until response or timeout
    String response = documents->get(*aClient, parent, path, options);
    
    // Log response details immediately for debugging
    Serial.print(F("[Firestore] getAsset response length: "));
    Serial.println(response.length());
    
    // Log raw response (first 1000 chars) even if empty
    if (response.length() > 0) {
        Serial.print(F("[Firestore] getAsset raw response (first 1000 chars): "));
        String preview = response.length() > 1000 ? response.substring(0, 1000) : response;
        Serial.println(preview);
        
        // Also log hex dump of first 200 bytes to see exact data
        Serial.print(F("[Firestore] getAsset hex dump (first 200 bytes): "));
        int dumpLen = response.length() < 200 ? response.length() : 200;
        for (int i = 0; i < dumpLen; i++) {
            if (response[i] < 0x10) Serial.print('0');
            Serial.print((unsigned char)response[i], HEX);
            Serial.print(' ');
            if ((i + 1) % 32 == 0) Serial.println();
        }
        Serial.println();
    } else {
        Serial.println(F("[Firestore] getAsset raw response: (EMPTY - no data received)"));
    }
    
    // Check for async client errors first (like getDeviceDoc does)
    int errorCode = aClient->lastError().code();
    if (errorCode != 0) {
        Serial.print(F("[Firestore] getAsset failed: id="));
        Serial.print(assetId);
        Serial.print(F(" path="));
        Serial.print(path);
        Serial.print(F(" errorCode="));
        Serial.print(errorCode);
        Serial.print(F(" errorMsg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    
    // Check if response is empty - this shouldn't happen if document exists
    if (response.length() == 0) {
        Serial.print(F("[Firestore] getAsset empty response: id="));
        Serial.print(assetId);
        Serial.print(F(" path="));
        Serial.print(path);
        Serial.print(F(" (document may not exist or network timeout)"));
        Serial.println();
        Serial.print(F("[Firestore] Full path should be: projects/"));
        Serial.print(projectId);
        Serial.print(F("/databases/(default)/documents/"));
        Serial.println(path);
        Serial.print(F("[Firestore] Compare with working getDeviceDoc path: projects/"));
        Serial.print(projectId);
        Serial.print(F("/databases/(default)/documents/"));
        Serial.println(getDevicePath());
        
        // Try to get more info from async client
        Serial.print(F("[Firestore] AsyncClient status - code: "));
        Serial.print(errorCode);
        Serial.print(F(", message: "));
        Serial.println(aClient->lastError().message());
        
        return false;
    }
    
    DynamicJsonDocument doc(16384); // Increased from 8192 for larger assets
    DeserializationError error = deserializeJson(doc, response);
    if (error != DeserializationError::Ok) {
        Serial.print(F("[Firestore] getAsset parse error: id="));
        Serial.print(assetId);
        Serial.print(F(" error="));
        Serial.print(error.c_str());
        Serial.print(F(" responseLen="));
        Serial.println(response.length());
        Serial.print(F("[Firestore] getAsset parse error - raw response start: "));
        if (response.length() > 200) {
            Serial.println(response.substring(0, 200));
        } else {
            Serial.println(response);
        }
        return false;
    }
    
    // Log what keys are in the parsed JSON
    Serial.print(F("[Firestore] getAsset parsed JSON keys: "));
    JsonObject rootObj = doc.as<JsonObject>();
    for (JsonPair kv : rootObj) {
        Serial.print(kv.key().c_str());
        Serial.print(' ');
    }
    Serial.println();
    
    // Check if document exists (Firestore returns error object if not found)
    if (doc.containsKey("error")) {
        Serial.print(F("[Firestore] getAsset document not found: id="));
        Serial.print(assetId);
        Serial.print(F(" path="));
        Serial.print(path);
        Serial.print(F(" error="));
        Serial.println(doc["error"].as<String>());
        return false;
    }
    
    // Check for 'fields' key (required for Firestore document)
    if (!doc.containsKey("fields")) {
        Serial.print(F("[Firestore] getAsset response missing 'fields' key: id="));
        Serial.print(assetId);
        Serial.print(F(" available keys: "));
        for (JsonPair kv : doc.as<JsonObject>()) {
            Serial.print(kv.key().c_str());
            Serial.print(' ');
        }
        Serial.println();
        return false;
    }
    
    // Get fields object
    JsonObject fields = doc["fields"].as<JsonObject>();
    
    // Log what fields we found
    Serial.print(F("[Firestore] getAsset found fields: "));
    for (JsonPair kv : fields) {
        Serial.print(kv.key().c_str());
        Serial.print(' ');
    }
    Serial.println();
    if (fields.containsKey("type")) firestoreFieldToString(fields["type"].as<JsonObject>(), asset.type);
    if (fields.containsKey("encoding")) firestoreFieldToString(fields["encoding"].as<JsonObject>(), asset.encoding);

    DynamicJsonDocument flat(16384); // Increased for larger assets
    flat["type"] = asset.type;
    flat["encoding"] = asset.encoding;
    if (fields.containsKey("pixels")) {
        Serial.println(F("[Firestore] Found 'pixels' field, parsing..."));
        JsonArray pixels = flat.createNestedArray("pixels");
        appendFirestorePixelArray(pixels, fields["pixels"]);
        Serial.print(F("[Firestore] Parsed "));
        Serial.print(pixels.size());
        Serial.println(F(" pixels"));
    } else {
        Serial.println(F("[Firestore] No 'pixels' field found"));
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
    Serial.print(F("[Firestore] getAsset: id="));
    Serial.print(assetId);
    Serial.print(F(" type="));
    Serial.print(asset.type);
    Serial.print(F(" encoding="));
    Serial.print(asset.encoding);
    Serial.print(F(" pixelsJsonLen="));
    Serial.println(asset.pixelsJson.length());
    return true;
}

bool FirestoreRepo::checkConfigVersion(int& version) {
    bool dummy;
    return getDeviceDoc(version, dummy);
}

#endif // ENABLE_FIRESTORE
