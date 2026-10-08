#include "FirestoreRepo.h"
#include "FirestorePagination.h"
#include "SharedScreenContract.h"
#include "FirebaseClientWrap.h"
#include "PairingConfig.h"
#include <ArduinoJson.h>

#if !defined(ENABLE_FIRESTORE)
// Stubs when Firestore not enabled
FirestoreRepo::FirestoreRepo(FirebaseClientWrap* wrap, const String& projId, const String& devId)
    : wrap(wrap), projectId(projId), deviceId(devId) {
}
String FirestoreRepo::getDevicePath() const { return ""; }
String FirestoreRepo::getScreensPath() const { return ""; }
String FirestoreRepo::getAssetPath(const String&) const { return ""; }
String FirestoreRepo::getUserDevicePath(const String&) const { return ""; }
bool FirestoreRepo::getDeviceDoc(DeviceDoc& out) { out = DeviceDoc(); return false; }
bool FirestoreRepo::createDeviceDoc(const String&) { return false; }
bool FirestoreRepo::updateDeviceCapability(bool) { return false; }
bool FirestoreRepo::updateBrightness(uint8_t) { return false; }
bool FirestoreRepo::claimDevice(const String&) { return false; }
bool FirestoreRepo::getScreens(std::vector<ScreenConfig>&) { return false; }
bool FirestoreRepo::readSharingState(const String&,DeviceDoc&) { return false; }
void FirestoreRepo::sharingSnapshot(DeviceDoc&) const {}
bool FirestoreRepo::getAsset(const String&, AssetData&, const String&) { return false; }
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

void FirestoreRepo::sharingSnapshot(DeviceDoc& out) const {
    out.sharingPairId=sharingState.sharingPairId;out.sharingVersion=sharingState.sharingVersion;out.sharingActive=sharingState.sharingActive;
}
bool FirestoreRepo::readSharingState(const String& pairId, DeviceDoc& out) {
    DeviceDoc next;
    next.sharingPairId=pairId;
    if(!pairId.isEmpty()) {
        auto* documents=static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
        auto* client=wrap->getAsyncClient();if(!documents||!client)return false;
        Firestore::Parent parent(projectId, "");
        GetDocumentOptions options(DocumentMask("schemaVersion,state,contentVersion,deviceA,deviceB"));
        String raw=documents->get(*client,parent,"sharingPairs/"+pairId,options);
        int code=client->lastError().code();
        if(code!=404) {
            if(code!=0||raw.isEmpty())return false;
            JsonDocument doc;if(deserializeJson(doc,raw)||doc.overflowed())return false;
            JsonObject f=doc["fields"].as<JsonObject>();
            if(f["schemaVersion"]["integerValue"].as<int>()!=1)return false;
            String a=f["deviceA"]["stringValue"].as<String>(),b=f["deviceB"]["stringValue"].as<String>();
            if(deviceId!=a&&deviceId!=b)return false;
            String state=f["state"]["stringValue"].as<String>();
            if(state!="ACTIVE"&&state!="PENDING"&&state!="CLOSING"&&state!="REVOKED")return false;
            if(!firestoreFieldToInt(f["contentVersion"].as<JsonObject>(),next.sharingVersion)||next.sharingVersion<0)return false;
            next.sharingActive=state=="ACTIVE";
        }
    }
    sharingState=next;sharingSnapshot(out);return true;
}

bool FirestoreRepo::getScreens(std::vector<ScreenConfig>& screens) {
    if (wrap == nullptr) return false;
    FirebaseFirestoreType* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (documents == nullptr || aClient == nullptr) return false;

    Firestore::Parent parent(projectId, "");
    std::vector<ScreenConfig> collected;
    String pageToken;
    do {
    ListDocumentsOptions listOpts;
    listOpts.pageSize(4).mask(DocumentMask("sharedScreenId,type,order,enabled,isShared,durationMs,assetId,defaultAssetId,availableAssetIds,allowManualSwitch,config"));
    if (!pageToken.isEmpty()) listOpts.pageToken(pageToken);
    String response = documents->list(*aClient, parent, getScreensPath(), listOpts);
    if (aClient->lastError().code() != 0 || response.isEmpty()) return false;
    JsonDocument doc;
    if (deserializeJson(doc,response) || doc.overflowed()) return false;
    if (!doc.is<JsonObject>() || (!doc["documents"].isNull() && !doc["documents"].is<JsonArray>())) return false;
    if (!readFirestorePageToken(doc["nextPageToken"], pageToken)) return false;
    JsonArray arr = doc["documents"].as<JsonArray>();
    for (JsonVariant docVar : arr) {
        JsonObject docObj = docVar.as<JsonObject>();
        ScreenConfig sc;
        sc.id = "";
        sc.type = "";
        sc.order = 0;
        sc.enabled = true;
        sc.durationMs = SCREEN_DEFAULT_DURATION_MS;
        sc.assetId = "";
        sc.defaultAssetId = "";
        sc.currentAssetIndex = 0;
        sc.availableAssetIds.clear();
        sc.allowManualSwitch = true;
        sc.configJson = "";
        if (!docObj["name"].is<const char*>() || !docObj["fields"].is<JsonObject>()) return false;
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
            if (firestoreFieldToInt(fields["durationMs"].as<JsonObject>(), d)) {
                // Clamp up, so a too-small value cannot spin the playlist.
                sc.durationMs = d <= 0 ? 0 : ((d < SCREEN_MIN_DURATION_MS) ? SCREEN_MIN_DURATION_MS : d);
            }
        }
        if (!fields["isShared"].isNull()) firestoreFieldToBool(fields["isShared"].as<JsonObject>(),sc.isShared);
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
        if (!fields["sharedScreenId"].isNull()) {
            sc.sharedScreenId=fields["sharedScreenId"]["stringValue"].as<String>();
            if(sc.sharedScreenId.isEmpty())return false;
            if(!sharingState.sharingActive)continue;
            GetDocumentOptions options(DocumentMask("schemaVersion,state,pairId,type,availableAssetIds,defaultAssetId,allowManualSwitch"));
            String raw=documents->get(*aClient,parent,"sharedScreens/"+sc.sharedScreenId,options);
            if(aClient->lastError().code()!=0||raw.isEmpty())return false;
            JsonDocument sharedDoc;if(deserializeJson(sharedDoc,raw)||sharedDoc.overflowed())return false;
            JsonObjectConst sf=sharedDoc["fields"].as<JsonObjectConst>();
            if(sf["state"]["stringValue"].as<String>()=="REVOKED")continue;
            if(sf["state"]["stringValue"].as<String>()!="ACTIVE"||sf["pairId"]["stringValue"].as<String>()!=sharingState.sharingPairId||!resolveSharedFields(sf,sc))return false;
        }
        if (sc.id.isEmpty() || sc.type.isEmpty()) return false;
        collected.push_back(std::move(sc));
    }
    } while (!pageToken.isEmpty());
    screens=std::move(collected);
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

bool FirestoreRepo::getAsset(const String& assetId, AssetData& asset, const String& knownRevision) {
    asset = AssetData();
    if (wrap == nullptr) return false;
    auto* documents = static_cast<FirebaseFirestoreType*>(wrap->getFirestore());
    auto* client = wrap->getAsyncClient();
    if (!documents || !client) return false;
    Firestore::Parent parent(projectId, "");
    String path = getAssetPath(assetId);
    auto read = [&](const char* mask) {
        GetDocumentOptions options{DocumentMask(mask)};
        String response = documents->get(*client, parent, path, options);
        if (client->lastError().code() != 0) {
            Serial.print(F("[Firestore] Asset request failed: ")); Serial.print(assetId);
            Serial.print(F(" code=")); Serial.println(client->lastError().code());
            wrap->resetTransport(); return String();
        }
        return response;
    };
    if (!knownRevision.isEmpty()) {
        // updateTime is response metadata and remains present with a field mask.
        String metadata = read("type");
        JsonDocument doc;
        if (metadata.isEmpty() || deserializeJson(doc, metadata.begin()) || doc.overflowed() ||
            !doc["fields"].is<JsonObject>() || !doc["updateTime"].is<const char*>()) return false;
        if (knownRevision == doc["updateTime"].as<const char*>()) {
            asset.unchanged = true;
            Serial.print(F("[Config] Asset unchanged: ")); Serial.println(assetId);
            return true;
        }
    }
    String response = read("type,encoding,pixels,pixelsPacked,basePixels,basePixelsPacked,frames,frameDeltasPacked,frameDurationsMs,frameCount,loop");
    if (response.isEmpty()) return false;
    JsonDocument doc;
    // Arduino String's mutable buffer enables zero-copy ArduinoJson parsing.
    // It stays alive until all pixels and revision strings have been copied.
    auto error = deserializeJson(doc, response.begin());
    if (error || doc.overflowed() || !doc["fields"].is<JsonObject>() ||
        !doc["updateTime"].is<const char*>()) {
        Serial.print(F("[Firestore] Asset response invalid: ")); Serial.print(assetId);
        Serial.print(F(" error=")); Serial.println(error.c_str()); return false;
    }
    JsonObject fields = doc["fields"].as<JsonObject>();
    const char* encoding = fields["encoding"]["stringValue"].as<const char*>();
    AssetCache parser;
    bool valid = false;
    if (encoding && (strcmp(encoding, "SPARSE_PACKED_V1") == 0 || strcmp(encoding, "DELTA_SPARSE_PACKED_V1") == 0)) {
        valid = parser.parseFirestorePackedAsset(assetId, fields, asset.content);
    } else {
        // Existing unpacked assets retain their compatibility decoder. Packed
        // app-authored content takes the lower-memory path above.
        JsonDocument flat;
        flat["type"] = fields["type"]["stringValue"];
        flat["encoding"] = fields["encoding"]["stringValue"];
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
                        int d = 0; firestoreFieldToInt(ffields["delayMs"].as<JsonObject>(), d);
                        frameObj["delayMs"] = d;
                    }
                    if (!ffields["pixels"].isNull()) {
                        JsonArray px = frameObj["pixels"].to<JsonArray>();
                        appendFirestorePixelArray(px, ffields["pixels"]);
                    }
                }
            }
        }
        valid = !flat.overflowed() && parser.parseAssetObject(assetId, flat.as<JsonObject>(), asset.content);
    }
    if (!valid) return false;
    asset.content.sourceRevision = doc["updateTime"].as<const char*>();
    if (asset.content.sourceRevision.isEmpty()) return false;
    Serial.print(F("[Config] Asset downloaded: ")); Serial.println(assetId);
    return true;
}

bool FirestoreRepo::checkConfigVersion(DeviceDoc& out) {
    return getDeviceDoc(out);
}

#endif // ENABLE_FIRESTORE
