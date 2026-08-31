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
bool FirestoreRepo::getDeviceDoc(DeviceDoc& out) { out = DeviceDoc(); return false; }
bool FirestoreRepo::createDeviceDoc(const String&) { return false; }
bool FirestoreRepo::updateDeviceCapability(bool) { return false; }
bool FirestoreRepo::updateBrightness(uint8_t) { return false; }
bool FirestoreRepo::claimDevice(const String&) { return false; }
bool FirestoreRepo::getScreens(std::vector<ScreenConfig>&) { return false; }
bool FirestoreRepo::getSharedScreen(const String&, const String&, SharedScreenConfig&) { return false; }
bool FirestoreRepo::getAsset(const String&, AssetData&) { return false; }
bool FirestoreRepo::checkConfigVersion(DeviceDoc& out) { return getDeviceDoc(out); }
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
    if (!field["stringValue"].isNull()) {
        out = field["stringValue"].as<String>();
        return true;
    }
    if (!field["integerValue"].isNull()) {
        out = field["integerValue"].as<String>();
        return true;
    }
    return false;
}

static bool firestoreFieldToInt(const JsonObject& field, int& out) {
    if (!field["integerValue"].isNull()) {
        out = field["integerValue"].as<int>();
        return true;
    }
    return false;
}

static bool firestoreFieldToBool(const JsonObject& field, bool& out) {
    if (!field["booleanValue"].isNull()) {
        out = field["booleanValue"].as<bool>();
        return true;
    }
    return false;
}

bool FirestoreRepo::getDeviceDoc(DeviceDoc& out) {
    // Reset up front so every failure path below leaves the sentinels in place,
    // which the caller reads as "the doc said nothing" and keeps its cached
    // values rather than resetting them.
    out = DeviceDoc();
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
        return false;
    }

    JsonDocument doc;
    if (deserializeJson(doc, response) != DeserializationError::Ok) {
        Serial.println(F("[Claiming] getDeviceDoc parse failed"));
        return false;
    }
    if (doc["fields"].isNull()) {
        Serial.println(F("[Claiming] getDeviceDoc response missing 'fields'"));
        return false;
    }

    JsonObject fields = doc["fields"].as<JsonObject>();
    if (!fields["configVersion"].isNull()) {
        firestoreFieldToInt(fields["configVersion"].as<JsonObject>(), out.configVersion);
    }
    if (!fields["tzPosix"].isNull()) {
        firestoreFieldToString(fields["tzPosix"].as<JsonObject>(), out.tzPosix);
    }
    if (!fields["brightness"].isNull()) {
        firestoreFieldToInt(fields["brightness"].as<JsonObject>(), out.brightness);
    }
    if (!fields["hw"].isNull()) {
        JsonObject hw = fields["hw"].as<JsonObject>();
        if (!hw["mapValue"].isNull() && !hw["mapValue"]["fields"].isNull()) {
            JsonObject hwFields = hw["mapValue"]["fields"].as<JsonObject>();
            if (!hwFields["bme680"].isNull()) {
                firestoreFieldToBool(hwFields["bme680"].as<JsonObject>(), out.bme680Present);
            }
        }
    }
    // Same nested-map shape as hw above. Partial maps keep their defaults
    // rather than being rejected, so an older app that writes fewer keys still
    // gives a usable schedule.
    if (!fields["sleepMode"].isNull()) {
        JsonObject sleepField = fields["sleepMode"].as<JsonObject>();
        if (!sleepField["mapValue"].isNull() && !sleepField["mapValue"]["fields"].isNull()) {
            JsonObject sleepFields = sleepField["mapValue"]["fields"].as<JsonObject>();
            out.hasSleep = true;
            if (!sleepFields["enabled"].isNull()) {
                firestoreFieldToBool(sleepFields["enabled"].as<JsonObject>(), out.sleep.enabled);
            }
            if (!sleepFields["startMinute"].isNull()) {
                firestoreFieldToInt(sleepFields["startMinute"].as<JsonObject>(), out.sleep.startMinute);
            }
            if (!sleepFields["endMinute"].isNull()) {
                firestoreFieldToInt(sleepFields["endMinute"].as<JsonObject>(), out.sleep.endMinute);
            }
            int sleepBrightness = DEFAULT_SLEEP_BRIGHTNESS;
            if (!sleepFields["brightness"].isNull()) {
                firestoreFieldToInt(sleepFields["brightness"].as<JsonObject>(), sleepBrightness);
            }
            out.sleep.brightness = (uint8_t)constrain(sleepBrightness, 0, 255);
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

bool FirestoreRepo::updateBrightness(uint8_t brightness) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    Firestore::Parent parent(projectId, "");
    // Field-scoped mask, so configVersion and everything the app owns are left
    // untouched - see the note on the declaration.
    DocumentMask updateMask("brightness");
    DocumentMask mask;
    Precondition precondition;
    PatchDocumentOptions patchOptions(updateMask, mask, precondition);
    Document<Values::Value> doc;
    doc.add("brightness", Values::Value(Values::IntegerValue(brightness)));

    String path = getDevicePath();
    documents->patch(*aClient, parent, path, patchOptions, doc);
    if (aClient->lastError().code() != 0) {
        Serial.print(F("[Firestore] updateBrightness failed, code="));
        Serial.println(aClient->lastError().code());
        return false;
    }
    return true;
}

bool FirestoreRepo::claimDevice(const String& uid) {
    if (wrap == nullptr || uid.length() == 0) {
        Serial.println(F("[Claiming] claimDevice: wrap null or uid empty"));
        return false;
    }
    Serial.print(F("[Claiming] Ensuring device doc exists..."));
    DeviceDoc existing;
    if (!getDeviceDoc(existing)) {
        Serial.println(F(" getDeviceDoc failed, creating device doc"));
        if (!createDeviceDoc(FW_VERSION)) {
            Serial.println(F("[Claiming] createDeviceDoc failed"));
            return false;
        }
        Serial.println(F("[Claiming] createDeviceDoc ok"));
    } else {
        Serial.print(F(" ok (configVersion="));
        Serial.print(existing.configVersion);
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
    // The membership doc survives reboots, so every boot after the first gets
    // ALREADY_EXISTS. That is the claim already being in place - the outcome
    // this call wants - not a failure. FirebaseClient reports HTTP statuses as
    // the error code but has no constant for 409, hence the literal.
    const int kHttpConflict = 409;
    if (errCode == kHttpConflict) {
        Serial.println(F("[Claiming] Device already claimed by this user"));
        return true;
    }
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

    JsonDocument doc;
    if (deserializeJson(doc, response) != DeserializationError::Ok) {
        Serial.println(F("[Firestore] getScreens: JSON parse error"));
        return false;
    }
    if (doc["documents"].isNull()) {
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
        sc.durationMs = SCREEN_DEFAULT_DURATION_MS;
        sc.pairId = "";
        sc.sharedScreenId = "";
        sc.assetId = "";
        sc.defaultAssetId = "";
        sc.currentAssetIndex = 0;
        sc.availableAssetIds.clear();
        sc.allowManualSwitch = true;
        sc.configJson = "";
        if (docObj["name"].isNull() || docObj["fields"].isNull()) continue;
        String name = docObj["name"].as<String>();
        int lastSlash = name.lastIndexOf('/');
        if (lastSlash >= 0) sc.id = name.substring(lastSlash + 1);
        JsonObject fields = docObj["fields"].as<JsonObject>();
        if (!fields["type"].isNull()) {
            firestoreFieldToString(fields["type"].as<JsonObject>(), sc.type);
            // Normalize to uppercase for consistent comparison
            sc.type.toUpperCase();
        }
        if (!fields["order"].isNull()) firestoreFieldToInt(fields["order"].as<JsonObject>(), sc.order);
        if (!fields["enabled"].isNull()) firestoreFieldToBool(fields["enabled"].as<JsonObject>(), sc.enabled);
        if (!fields["durationMs"].isNull()) {
            int d = 0;
            if (firestoreFieldToInt(fields["durationMs"].as<JsonObject>(), d) && d > 0) {
                // Clamp up, so a too-small value cannot spin the playlist.
                sc.durationMs = (d < SCREEN_MIN_DURATION_MS) ? SCREEN_MIN_DURATION_MS : d;
            }
        }
        if (!fields["pairId"].isNull()) firestoreFieldToString(fields["pairId"].as<JsonObject>(), sc.pairId);
        if (!fields["sharedScreenId"].isNull()) firestoreFieldToString(fields["sharedScreenId"].as<JsonObject>(), sc.sharedScreenId);
        if (!fields["assetId"].isNull()) firestoreFieldToString(fields["assetId"].as<JsonObject>(), sc.assetId);
        // Asset pool lives on the screen document, so IMAGE/ANIMATION screens
        // can cycle several assets without depending on a pair.
        if (!fields["defaultAssetId"].isNull()) firestoreFieldToString(fields["defaultAssetId"].as<JsonObject>(), sc.defaultAssetId);
        if (!fields["allowManualSwitch"].isNull()) firestoreFieldToBool(fields["allowManualSwitch"].as<JsonObject>(), sc.allowManualSwitch);
        if (!fields["availableAssetIds"].isNull() && !fields["availableAssetIds"]["arrayValue"].isNull()) {
            JsonArray arr = fields["availableAssetIds"]["arrayValue"]["values"].as<JsonArray>();
            for (JsonObject v : arr) {
                if (!v["stringValue"].isNull()) {
                    sc.availableAssetIds.push_back(v["stringValue"].as<String>());
                }
            }
        }
        // Load config JSON for CLOCK/SENSOR screens
        if (!fields["config"].isNull()) {
            // Firestore stores nested objects as mapValue with fields
            JsonObject configField = fields["config"].as<JsonObject>();
            if (!configField["mapValue"].isNull() && !configField["mapValue"]["fields"].isNull()) {
                JsonObject configFields = configField["mapValue"]["fields"].as<JsonObject>();
                JsonDocument configDoc;
                // Convert Firestore mapValue fields to flat JSON
                JsonObject configObj = configDoc.to<JsonObject>();
                // Copy all fields from Firestore format to JSON format
                for (JsonPair kv : configFields) {
                    String key = kv.key().c_str();
                    JsonObject fieldObj = kv.value().as<JsonObject>();
                    if (!fieldObj["booleanValue"].isNull()) {
                        configObj[key] = fieldObj["booleanValue"].as<bool>();
                    } else if (!fieldObj["integerValue"].isNull()) {
                        configObj[key] = fieldObj["integerValue"].as<uint32_t>();
                    } else if (!fieldObj["stringValue"].isNull()) {
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

    JsonDocument doc;
    if (deserializeJson(doc, response) != DeserializationError::Ok) return false;
    if (doc["fields"].isNull()) return false;

    JsonObject fields = doc["fields"].as<JsonObject>();
    if (!fields["type"].isNull()) firestoreFieldToString(fields["type"].as<JsonObject>(), config.type);
    if (!fields["defaultAssetId"].isNull()) firestoreFieldToString(fields["defaultAssetId"].as<JsonObject>(), config.defaultAssetId);
    if (!fields["allowManualSwitch"].isNull()) firestoreFieldToBool(fields["allowManualSwitch"].as<JsonObject>(), config.allowManualSwitch);
    if (!fields["loop"].isNull()) firestoreFieldToBool(fields["loop"].as<JsonObject>(), config.loop);
    if (!fields["availableAssetIds"].isNull() && !fields["availableAssetIds"]["arrayValue"].isNull()) {
        JsonArray arr = fields["availableAssetIds"]["arrayValue"]["values"].as<JsonArray>();
        for (JsonObject v : arr) {
            if (!v["stringValue"].isNull()) {
                config.availableAssetIds.push_back(v["stringValue"].as<String>());
            }
        }
    }
    return true;
}

// Convert Firestore arrayValue of {color, index} objects to flat JSON array for AssetCache::parseAsset
// Format: [{color: 55807, index: 71}, {color: 55807, index: 73}]
static void appendFirestorePixelArray(JsonArray& out, JsonVariant firestoreArr) {
    if (firestoreArr["arrayValue"].isNull() || firestoreArr["arrayValue"]["values"].isNull()) {
        Serial.println(F("[Firestore] appendFirestorePixelArray: no arrayValue/values"));
        return;
    }
    JsonArray values = firestoreArr["arrayValue"]["values"].as<JsonArray>();
    Serial.print(F("[Firestore] appendFirestorePixelArray: processing "));
    Serial.print(values.size());
    Serial.println(F(" pixel objects"));
    for (JsonVariant v : values) {
        // Check if it's a mapValue (object format: {color: X, index: Y})
        if (!v["mapValue"].isNull() && !v["mapValue"]["fields"].isNull()) {
            JsonObject fields = v["mapValue"]["fields"].as<JsonObject>();
            int index = -1;
            uint32_t color = 0;
            
            if (!fields["index"].isNull()) {
                int idx;
                if (firestoreFieldToInt(fields["index"].as<JsonObject>(), idx)) {
                    index = idx;
                }
            }
            if (!fields["color"].isNull()) {
                // Color is stored as integerValue in Firestore
                JsonObject colorField = fields["color"].as<JsonObject>();
                if (!colorField["integerValue"].isNull()) {
                    color = colorField["integerValue"].as<uint32_t>();
                } else if (!colorField["stringValue"].isNull()) {
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
        else if (!v["arrayValue"].isNull() && !v["arrayValue"]["values"].isNull()) {
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
    // No DocumentMask, deliberately.
    //
    // FirebaseClient formats the whole request line into a buffer sized from a
    // hardcoded 300 (RequestHandler.h: printTo(val[header], 300, "%s%s%s
    // HTTP/1.1\r\n", ...)), so anything past ~331 characters is silently
    // truncated by vsnprintf - taking the " HTTP/1.1\r\n" terminator with it.
    // Google's frontend answers that malformed request line with an HTML 400,
    // and the half-spoken connection then wedges the next synchronous get.
    //
    // The document path alone is ~81 characters, so a mask listing every field
    // both encodings need came to ~388 and broke every asset fetch. Masking
    // only saves the handful of metadata fields (name, ownerUid, tags, width,
    // height, createdAt) - a few hundred bytes against a payload we size the
    // JSON documents from anyway. Not worth reintroducing a length cliff that
    // depends on how long an asset id happens to be.
    //
    // If you add a mask back, keep path + query + 11 under 331 characters.
    GetDocumentOptions options;
    String path = getAssetPath(assetId);
    Serial.print(F("[Firestore] getAsset: freeHeap="));
    Serial.print(ESP.getFreeHeap());
    Serial.print(F(" largestBlock="));
    Serial.println(heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
    Serial.print(F("[Firestore] getAsset: querying path="));
    Serial.print(path);
    Serial.print(F(" projectId="));
    Serial.println(projectId);
    // Call get() - exact same pattern as getDeviceDoc which works
    // Note: FirebaseClient get() is synchronous and blocks until response or timeout
    String response = documents->get(*aClient, parent, path, options);

    // A rejected request leaves the socket half-spoken: the next synchronous
    // get on it blocks past its own read timeout and takes the whole device
    // with it. Drop the connection so the following fetch starts clean.
    if (aClient->lastError().code() != 0 && wrap != nullptr) {
        Serial.print(F("[Firestore] getAsset: request failed (code="));
        Serial.print(aClient->lastError().code());
        Serial.println(F("), resetting transport"));
        wrap->resetTransport();
    }
    
    // Log response details immediately for debugging
    Serial.print(F("[Firestore] getAsset response length: "));
    Serial.println(response.length());
    
#if FIRESTORE_DEBUG_ASSETS
    // Instrumentation from an asset-fetch hunt, off by default: the preview and
    // the hex dump together are ~200 ms of blocking serial per call at 115200
    // baud, which shifts the timing they exist to measure. An empty response is
    // reported in full by the branch below either way.
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
    }
#endif
    
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
        // An empty body with errorCode 0 is the signature of the client failing
        // to grow its payload String: without PSRAM it reallocs in 2KB steps
        // with no reservation, so a large document needs a contiguous block
        // that a TLS-fragmented heap cannot supply. Largest free block matters
        // more than total free heap here.
        Serial.print(F("[Firestore] Heap at failure: free="));
        Serial.print(ESP.getFreeHeap());
        Serial.print(F(" largestFreeBlock="));
        Serial.println(ESP.getMaxAllocHeap());
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
    
    // ArduinoJson 7 grows this as it parses. It used to reserve a fixed 16KB
    // here and another for `flat` below - 32KB on every asset fetch, on top of
    // the ~40KB mbedTLS holds for the TLS session, which on a plain ESP32 was
    // enough to push a later allocation into failure. A failed String
    // allocation shows up as a truncated request header, which Google's
    // frontend rejects with an HTML 400 rather than a Firestore JSON error.
    JsonDocument doc;
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
    if (!doc["error"].isNull()) {
        Serial.print(F("[Firestore] getAsset document not found: id="));
        Serial.print(assetId);
        Serial.print(F(" path="));
        Serial.print(path);
        Serial.print(F(" error="));
        Serial.println(doc["error"].as<String>());
        return false;
    }
    
    // Check for 'fields' key (required for Firestore document)
    if (doc["fields"].isNull()) {
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

    // `doc` copied everything it needs, so the raw response is dead weight from
    // here on and `flat` is about to be allocated. Freeing it first keeps the
    // peak to one document plus one, not two plus the response.
    response = String();
    
    // Log what fields we found
    Serial.print(F("[Firestore] getAsset found fields: "));
    for (JsonPair kv : fields) {
        Serial.print(kv.key().c_str());
        Serial.print(' ');
    }
    Serial.println();
    if (!fields["type"].isNull()) firestoreFieldToString(fields["type"].as<JsonObject>(), asset.type);
    if (!fields["encoding"].isNull()) firestoreFieldToString(fields["encoding"].as<JsonObject>(), asset.encoding);

    // The flattened form is strictly smaller than the Firestore-wrapped
    // response it is built from.
    JsonDocument flat;
    flat["type"] = asset.type;
    flat["encoding"] = asset.encoding;
    if (!fields["pixelsPacked"].isNull()) {
        // SPARSE_PACKED_V1 carries the whole image as one string, so it is
        // copied straight across - no per-pixel rebuild needed.
        String packed;
        if (firestoreFieldToString(fields["pixelsPacked"].as<JsonObject>(), packed)) {
            flat["pixelsPacked"] = packed;
            Serial.print(F("[Firestore] Found 'pixelsPacked' field, chars="));
            Serial.print(packed.length());
            Serial.print(F(" pixels="));
            Serial.println(packed.length() / 8);
        } else {
            Serial.println(F("[Firestore] 'pixelsPacked' present but not a string"));
        }
    }
    if (!fields["pixels"].isNull()) {
        Serial.println(F("[Firestore] Found 'pixels' field, parsing..."));
        JsonArray pixels = flat["pixels"].to<JsonArray>();
        appendFirestorePixelArray(pixels, fields["pixels"]);
        Serial.print(F("[Firestore] Parsed "));
        Serial.print(pixels.size());
        Serial.println(F(" pixels"));
    } else {
        Serial.println(F("[Firestore] No 'pixels' field found"));
    }
    if (!fields["basePixels"].isNull()) {
        JsonArray basePixels = flat["basePixels"].to<JsonArray>();
        appendFirestorePixelArray(basePixels, fields["basePixels"]);
    }
    if (!fields["frames"].isNull()) {
        JsonArray frames = flat["frames"].to<JsonArray>();
        JsonArray firestoreFrames = fields["frames"]["arrayValue"]["values"].as<JsonArray>();
        for (JsonVariant fv : firestoreFrames) {
            JsonObject frameObj = frames.add<JsonObject>();
            if (!fv["mapValue"].isNull() && !fv["mapValue"]["fields"].isNull()) {
                JsonObject ffields = fv["mapValue"]["fields"].as<JsonObject>();
                if (!ffields["delayMs"].isNull()) {
                    int d; firestoreFieldToInt(ffields["delayMs"].as<JsonObject>(), d);
                    frameObj["delayMs"] = d;
                }
                if (!ffields["pixels"].isNull()) {
                    JsonArray px = frameObj["pixels"].to<JsonArray>();
                    appendFirestorePixelArray(px, ffields["pixels"]);
                }
            }
        }
    }
    if (!fields["loop"].isNull()) {
        bool l; firestoreFieldToBool(fields["loop"].as<JsonObject>(), l);
        flat["loop"] = l;
    }
    // DELTA_SPARSE_PACKED_V1: the first frame in full plus one packed
    // transition per later frame, all as plain strings, so an animation costs
    // the same shape of transfer as an image rather than a map per pixel.
    if (!fields["basePixelsPacked"].isNull()) {
        String packed;
        if (firestoreFieldToString(fields["basePixelsPacked"].as<JsonObject>(), packed)) {
            flat["basePixelsPacked"] = packed;
            Serial.print(F("[Firestore] Found 'basePixelsPacked', chars="));
            Serial.println(packed.length());
        } else {
            Serial.println(F("[Firestore] 'basePixelsPacked' present but not a string"));
        }
    }
    if (!fields["frameDeltasPacked"].isNull()) {
        JsonArray deltas = flat["frameDeltasPacked"].to<JsonArray>();
        JsonVariant src = fields["frameDeltasPacked"];
        if (!src["arrayValue"].isNull() && !src["arrayValue"]["values"].isNull()) {
            size_t totalChars = 0;
            for (JsonVariant v : src["arrayValue"]["values"].as<JsonArray>()) {
                String delta;
                // An absent stringValue means an empty transition, which is a
                // legitimate frame that changes nothing.
                if (!firestoreFieldToString(v.as<JsonObject>(), delta)) delta = "";
                totalChars += delta.length();
                deltas.add(delta);
            }
            Serial.print(F("[Firestore] Found 'frameDeltasPacked', deltas="));
            Serial.print(deltas.size());
            Serial.print(F(" chars="));
            Serial.println(totalChars);
        }
    }
    if (!fields["frameDurationsMs"].isNull()) {
        JsonArray durations = flat["frameDurationsMs"].to<JsonArray>();
        JsonVariant src = fields["frameDurationsMs"];
        if (!src["arrayValue"].isNull() && !src["arrayValue"]["values"].isNull()) {
            for (JsonVariant v : src["arrayValue"]["values"].as<JsonArray>()) {
                int ms = 0;
                firestoreFieldToInt(v.as<JsonObject>(), ms);
                durations.add(ms);
            }
        }
    }
    if (!fields["frameCount"].isNull()) {
        int count = 0;
        if (firestoreFieldToInt(fields["frameCount"].as<JsonObject>(), count)) {
            flat["frameCount"] = count;
        }
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

bool FirestoreRepo::checkConfigVersion(DeviceDoc& out) {
    return getDeviceDoc(out);
}

#endif // ENABLE_FIRESTORE
