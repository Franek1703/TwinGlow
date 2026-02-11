#include "RtdbRepo.h"
#include "FirebaseClientWrap.h"
#include <ArduinoJson.h>

#if !defined(ENABLE_DATABASE)
// Stub when RTDB not enabled
RtdbRepo::RtdbRepo(FirebaseClientWrap* wrap, const String& devId)
    : wrap(wrap), deviceId(devId) {
}
String RtdbRepo::getPresencePath() const { return ""; }
String RtdbRepo::getTelemetryPath() const { return ""; }
String RtdbRepo::getCommandsPath() const { return ""; }
String RtdbRepo::getPairEventsPath(const String& pairId) const { (void)pairId; return ""; }
bool RtdbRepo::updatePresence(bool) { return false; }
bool RtdbRepo::pushTelemetry(float, float, float, float) { return false; }
bool RtdbRepo::checkCommands() { return false; }
bool RtdbRepo::acknowledgeCommand(const String&, bool) { return false; }
bool RtdbRepo::sendToPair(const String&, const String&, const String&) { return false; }
#else

RtdbRepo::RtdbRepo(FirebaseClientWrap* wrap, const String& devId)
    : wrap(wrap), deviceId(devId) {
    if (wrap == nullptr || wrap->getRtdb() == nullptr) {
        Serial.println(F("[RtdbRepo] WARNING: wrap or RTDB is null"));
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

bool RtdbRepo::updatePresence(bool online) {
    if (wrap == nullptr) return false;
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) return false;
    DynamicJsonDocument doc(128);
    doc["online"] = online;
    doc["ts"] = millis();
    String jsonStr;
    serializeJson(doc, jsonStr);
    bool ok = rtdb->set(*aClient, getPresencePath(), jsonStr.c_str());
    return ok && aClient->lastError().code() == 0;
}

bool RtdbRepo::pushTelemetry(float temperature, float humidity, float pressure, float gas) {
    if (wrap == nullptr) return false;
    FirebaseRTDBType* rtdb = static_cast<FirebaseRTDBType*>(wrap->getRtdb());
    AsyncClientClass* aClient = wrap->getAsyncClient();
    if (rtdb == nullptr || aClient == nullptr) return false;
    DynamicJsonDocument doc(256);
    doc["temperature"] = round(temperature * 100) / 100.0;
    doc["humidity"] = round(humidity * 100) / 100.0;
    doc["pressure"] = round(pressure * 100) / 100.0;
    doc["gas"] = round(gas * 100) / 100.0;
    doc["ts"] = millis();
    String jsonStr;
    serializeJson(doc, jsonStr);
    bool ok = rtdb->set(*aClient, getTelemetryPath(), jsonStr.c_str());
    return ok && aClient->lastError().code() == 0;
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
