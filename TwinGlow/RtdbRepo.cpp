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
    
    // Set fields individually to avoid JSON parsing issues
    String path = getPresencePath();
    String onlinePath = path + "/online";
    String timestampPath = path + "/lastSeenMs";
    
    Serial.print(F("[RtdbRepo] Updating presence: "));
    Serial.print(path);
    Serial.print(F(" (online="));
    Serial.print(online);
    Serial.print(F(", lastSeenMs="));
    Serial.print(lastSeenMs);
    Serial.println(F(")"));
    
    // Set online field
    bool ok1 = rtdb->set(*aClient, onlinePath, online);
    int errorCode1 = aClient->lastError().code();
    
    // Set timestamp field
    bool ok2 = rtdb->set(*aClient, timestampPath, (long long)lastSeenMs);
    int errorCode2 = aClient->lastError().code();
    
    if (!ok1 || errorCode1 != 0) {
        Serial.print(F("[RtdbRepo] updatePresence FAILED (online), code="));
        Serial.print(errorCode1);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    
    if (!ok2 || errorCode2 != 0) {
        Serial.print(F("[RtdbRepo] updatePresence FAILED (timestamp), code="));
        Serial.print(errorCode2);
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
    
    // Set fields individually to avoid JSON parsing issues
    String path = getTelemetryPath();
    
    Serial.print(F("[RtdbRepo] Pushing telemetry: "));
    Serial.print(path);
    
    // Set each field individually
    bool ok1 = rtdb->set(*aClient, path + "/temperatureC", round(temperature * 100) / 100.0);
    int errorCode1 = aClient->lastError().code();
    bool ok2 = rtdb->set(*aClient, path + "/humidityPct", round(humidity * 100) / 100.0);
    int errorCode2 = aClient->lastError().code();
    bool ok3 = rtdb->set(*aClient, path + "/pressureHPa", round(pressure * 100) / 100.0);
    int errorCode3 = aClient->lastError().code();
    bool ok4 = rtdb->set(*aClient, path + "/gasOhms", round(gas * 100) / 100.0);
    int errorCode4 = aClient->lastError().code();
    bool ok5 = rtdb->set(*aClient, path + "/updatedMs", (long long)updatedMs);
    int errorCode5 = aClient->lastError().code();
    
    if (!ok1 || errorCode1 != 0) {
        Serial.print(F("[RtdbRepo] pushTelemetry FAILED (temperature), code="));
        Serial.print(errorCode1);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    if (!ok2 || errorCode2 != 0) {
        Serial.print(F("[RtdbRepo] pushTelemetry FAILED (humidity), code="));
        Serial.print(errorCode2);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    if (!ok3 || errorCode3 != 0) {
        Serial.print(F("[RtdbRepo] pushTelemetry FAILED (pressure), code="));
        Serial.print(errorCode3);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    if (!ok4 || errorCode4 != 0) {
        Serial.print(F("[RtdbRepo] pushTelemetry FAILED (gas), code="));
        Serial.print(errorCode4);
        Serial.print(F(" msg="));
        Serial.println(aClient->lastError().message());
        return false;
    }
    if (!ok5 || errorCode5 != 0) {
        Serial.print(F("[RtdbRepo] pushTelemetry FAILED (timestamp), code="));
        Serial.print(errorCode5);
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
