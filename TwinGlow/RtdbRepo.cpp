#include "RtdbRepo.h"

RtdbRepo::RtdbRepo(void* rtdbInstance, const String& devId)
    : rtdb(rtdbInstance), deviceId(devId) {
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] WARNING: RTDB instance is nullptr"));
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

bool RtdbRepo::updatePresence(bool online) {
    if (rtdb == nullptr) return false;
    // TODO: FirebaseClient uses db.set(aClient, path, value) with String/JSON string. Integrate AsyncClient.
    (void)online;
    return false;
}

bool RtdbRepo::pushTelemetry(float temperature, float humidity, float pressure, float gas) {
    if (rtdb == nullptr) return false;
    // TODO: Build JSON with ArduinoJson, then db.set(aClient, path, jsonString). Integrate AsyncClient.
    (void)temperature;
    (void)humidity;
    (void)pressure;
    (void)gas;
    return false;
}

bool RtdbRepo::checkCommands() {
    if (rtdb == nullptr) return false;
    // TODO: db.get<String>(aClient, path) then parse with ArduinoJson. Integrate AsyncClient.
    return false;
}

bool RtdbRepo::acknowledgeCommand(const String& commandId, bool success) {
    if (rtdb == nullptr) return false;
    // TODO: Build JSON and db.set(aClient, path, jsonString). Integrate AsyncClient.
    (void)commandId;
    (void)success;
    return false;
}

bool RtdbRepo::sendToPair(const String& pairId, const String& screenId, const String& assetId) {
    if (rtdb == nullptr) return false;
    // TODO: Build JSON and db.push(aClient, path, jsonString). Integrate AsyncClient.
    (void)pairId;
    (void)screenId;
    (void)assetId;
    return false;
}
