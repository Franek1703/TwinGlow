#include "RtdbRepo.h"
#include "FirebaseClientWrap.h"
#include <ArduinoJson.h>
#include <time.h>

#if !defined(ENABLE_DATABASE)
// Stub when RTDB not enabled
RtdbRepo::RtdbRepo(FirebaseClientWrap* wrap, const String& devId)
    : wrap(wrap), deviceId(devId) {
}
String RtdbRepo::getPresencePath() const { return ""; }
String RtdbRepo::getTelemetryPath() const { return ""; }
String RtdbRepo::getCommandsPath() const { return ""; }
String RtdbRepo::getConfigPath() const { return ""; }
String RtdbRepo::getPairEventsPath(const String& pairId) const { (void)pairId; return ""; }
bool RtdbRepo::updatePresence(bool) { return false; }
bool RtdbRepo::pushTelemetry(float, float, float, float) { return false; }
bool RtdbRepo::getConfigRevision(int&) { return false; }
bool RtdbRepo::checkCommands() { return false; }
bool RtdbRepo::acknowledgeCommand(const String&, bool) { return false; }
bool RtdbRepo::sendToPair(const String&, const String&, const String&) { return false; }
#else

RtdbRepo::RtdbRepo(FirebaseClientWrap* wrap, const String& devId)
    : wrap(wrap), deviceId(devId) {
    if (wrap == nullptr) {
        Serial.println(F("[RtdbRepo] ERROR: wrap is null"));
    } else if (wrap->getRtdb() == nullptr) {
        Serial.println(F("[RtdbRepo] ERROR: RTDB is null - RTDB may not be initialized"));
    } else {
        Serial.print(F("[RtdbRepo] Initialized for device: "));
        Serial.println(deviceId);
    }
}

String RtdbRepo::getPresencePath() const {
    return "/presence/" + deviceId;
}

String RtdbRepo::getTelemetryPath() const {
    return "/telemetry/" + deviceId;
}

String RtdbRepo::getCommandsPath() const {
    return "/commands/" + deviceId;
}

String RtdbRepo::getPairEventsPath(const String& pairId) const {
    return "/pairs/" + pairId + "/events";
}

String RtdbRepo::getConfigPath() const {
    return "/config/" + deviceId + "/configVersion";
}

bool RtdbRepo::updatePresence(bool online) {
    if (wrap == nullptr) {
        Serial.println(F("[RtdbRepo] updatePresence: wrap is null"));
        return false;
    }
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) {
        Serial.println(F("[RtdbRepo] updatePresence: rtdb or aClient is null"));
        return false;
    }
    
    // Get epoch timestamp in milliseconds
    time_t now = time(nullptr);
    unsigned long long lastSeenMs = (now > 0) ? (unsigned long long)now * 1000 : millis();
    
    // Write one object instead of opening two sequential HTTPS operations.
    // object_t tells FirebaseClient that this is JSON (not a quoted string),
    // and the single PUT also keeps online/lastSeenMs consistent.
    String path = getPresencePath();
    
    Serial.print(F("[RtdbRepo] Updating presence: "));
    Serial.print(path);
    Serial.print(F(" (online="));
    Serial.print(online);
    Serial.print(F(", lastSeenMs="));
    Serial.print(lastSeenMs);
    Serial.println(F(")"));
    
    DynamicJsonDocument doc(128);
    doc["online"] = online;
    doc["lastSeenMs"] = lastSeenMs;
    String payload;
    serializeJson(doc, payload);

    bool ok = rtdb->set<object_t>(*aClient, path, object_t(payload));
    int errorCode = aClient->lastError().code();
    if (!ok || errorCode != 0) {
        Serial.print(F("[RtdbRepo] updatePresence FAILED, code="));
        Serial.print(errorCode);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    
    Serial.println(F("[RtdbRepo] updatePresence SUCCESS"));
    return true;
}

bool RtdbRepo::pushTelemetry(float temperature, float humidity, float pressure, float gas) {
    if (wrap == nullptr) {
        Serial.println(F("[RtdbRepo] pushTelemetry: wrap is null"));
        return false;
    }
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) {
        Serial.println(F("[RtdbRepo] pushTelemetry: rtdb or aClient is null"));
        return false;
    }
    
    // Get epoch timestamp in milliseconds
    time_t now = time(nullptr);
    unsigned long long updatedMs = (now > 0) ? (unsigned long long)now * 1000 : millis();
    
    // Send one object to minimize HTTPS handshakes and keep the sample atomic.
    String path = getTelemetryPath();
    
    Serial.print(F("[RtdbRepo] Pushing telemetry: "));
    Serial.print(path);
    
    DynamicJsonDocument doc(256);
    doc["temperatureC"] = round(temperature * 100) / 100.0;
    doc["humidityPct"] = round(humidity * 100) / 100.0;
    doc["pressureHPa"] = round(pressure * 100) / 100.0;
    doc["gasOhms"] = round(gas * 100) / 100.0;
    doc["updatedMs"] = updatedMs;
    String payload;
    serializeJson(doc, payload);

    bool ok = rtdb->set<object_t>(*aClient, path, object_t(payload));
    int errorCode = aClient->lastError().code();
    if (!ok || errorCode != 0) {
        Serial.print(F("[RtdbRepo] pushTelemetry FAILED, code="));
        Serial.print(errorCode);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    
    Serial.println(F("[RtdbRepo] pushTelemetry SUCCESS"));
    return true;
}

bool RtdbRepo::getConfigRevision(int& revision) {
    if (wrap == nullptr) return false;
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) return false;
    // Read as String rather than int: an absent node answers "null", which
    // get<int>() would flatten to 0 and make indistinguishable from a real 0.
    String raw = rtdb->get<String>(*aClient, getConfigPath());
    if (aClient->lastError().code() != 0) return false;
    raw.trim();
    if (raw.length() == 0 || raw == "null") return false;
    revision = raw.toInt();
    return true;
}

bool RtdbRepo::checkCommands() {
    if (wrap == nullptr) return false;
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) return false;
    String raw = rtdb->get<String>(*aClient, getCommandsPath());
    if (aClient->lastError().code() != 0) return false;
    if (raw.length() == 0 || raw == "null") return false;
    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, raw) != DeserializationError::Ok) return false;
    JsonObject obj = doc.as<JsonObject>();
    for (JsonPair kv : obj) {
        if (!kv.value().isNull()) return true; // at least one command
    }
    return false;
}

bool RtdbRepo::acknowledgeCommand(const String& commandId, bool success) {
    if (wrap == nullptr || commandId.length() == 0) return false;
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) return false;
    String path = getCommandsPath() + "/" + commandId;
    bool ok = rtdb->remove(*aClient, path);
    return ok && aClient->lastError().code() == 0;
}

bool RtdbRepo::sendToPair(const String& pairId, const String& screenId, const String& assetId) {
    if (wrap == nullptr || pairId.length() == 0) return false;
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) return false;
    DynamicJsonDocument doc(256);
    doc["screenId"] = screenId;
    doc["assetId"] = assetId;
    doc["ts"] = millis();
    String jsonStr;
    serializeJson(doc, jsonStr);
    String path = getPairEventsPath(pairId);
    String name = rtdb->push(*aClient, path, jsonStr.c_str());
    bool ok = name.length() > 0 && aClient->lastError().code() == 0;
    return ok;
}

#endif // ENABLE_DATABASE
