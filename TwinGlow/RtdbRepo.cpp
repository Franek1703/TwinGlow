#include "RtdbRepo.h"

RtdbRepo::RtdbRepo(void* rtdbInstance, const String& devId)
    : rtdb(rtdbInstance), deviceId(devId) {
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] WARNING: RTDB instance is nullptr"));
        Serial.println(F("[RtdbRepo] Update FirebaseTypes.h with correct class names"));
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
    Serial.print(F("[RtdbRepo] updatePresence(online="));
    Serial.print(online ? F("true") : F("false"));
    Serial.println(F(")"));
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] updatePresence: RTDB null, skip"));
        return false;
    }
    Serial.print(F("[RtdbRepo] updatePresence path="));
    Serial.println(getPresencePath());
    // TODO: FirebaseClient uses db.set(aClient, path, value) with String/JSON string. Integrate AsyncClient.
    (void)online;
    return false;
}

bool RtdbRepo::pushTelemetry(float temperature, float humidity, float pressure, float gas) {
    Serial.println(F("[RtdbRepo] pushTelemetry()"));
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] pushTelemetry: RTDB null, skip"));
        return false;
    }
    Serial.print(F("[RtdbRepo] pushTelemetry: T=")); Serial.print(temperature);
    Serial.print(F(" H=")); Serial.print(humidity);
    Serial.print(F(" P=")); Serial.print(pressure);
    Serial.print(F(" G=")); Serial.println(gas);
    Serial.print(F("[RtdbRepo] path="));
    Serial.println(getTelemetryPath());
    // TODO: Build JSON with ArduinoJson, then db.set(aClient, path, jsonString). Integrate AsyncClient.
    (void)temperature;
    (void)humidity;
    (void)pressure;
    (void)gas;
    return false;
}

bool RtdbRepo::checkCommands() {
    Serial.println(F("[RtdbRepo] checkCommands()"));
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] checkCommands: RTDB null, skip"));
        return false;
    }
    Serial.print(F("[RtdbRepo] path="));
    Serial.println(getCommandsPath());
    // TODO: db.get<String>(aClient, path) then parse with ArduinoJson. Integrate AsyncClient.
    return false;
}

bool RtdbRepo::acknowledgeCommand(const String& commandId, bool success) {
    Serial.print(F("[RtdbRepo] acknowledgeCommand(id="));
    Serial.print(commandId);
    Serial.print(F(" success="));
    Serial.print(success ? F("true") : F("false"));
    Serial.println(F(")"));
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] acknowledgeCommand: RTDB null, skip"));
        return false;
    }
    // TODO: Build JSON and db.set(aClient, path, jsonString). Integrate AsyncClient.
    (void)commandId;
    (void)success;
    return false;
}

bool RtdbRepo::sendToPair(const String& pairId, const String& screenId, const String& assetId) {
    Serial.print(F("[RtdbRepo] sendToPair(pair="));
    Serial.print(pairId);
    Serial.print(F(" screen=")); Serial.print(screenId);
    Serial.print(F(" asset=")); Serial.println(assetId);
    if (rtdb == nullptr) {
        Serial.println(F("[RtdbRepo] sendToPair: RTDB null, skip"));
        return false;
    }
    // TODO: Build JSON and db.push(aClient, path, jsonString). Integrate AsyncClient.
    (void)pairId;
    (void)screenId;
    (void)assetId;
    return false;
}
