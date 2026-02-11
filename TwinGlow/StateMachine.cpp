#include "StateMachine.h"
#include <Arduino.h>
#include <cstring>

StateMachine::StateMachine() : currentState(DeviceState::BOOT) {
    lastError[0] = '\0';
}

const char* StateMachine::getStateName() const {
    return stateToString(currentState);
}

void StateMachine::setState(DeviceState newState) {
    if (currentState != newState) {
        Serial.print("[FSM] State: ");
        Serial.print(stateToString(currentState));
        Serial.print(" -> ");
        Serial.println(stateToString(newState));
        currentState = newState;
    }
}

void StateMachine::transition(DeviceState newState) {
    setState(newState);
}

bool StateMachine::isProvisioning() const {
    return currentState == DeviceState::PROVISIONING_BLE;
}

bool StateMachine::isConnecting() const {
    return currentState == DeviceState::WIFI_CONNECTING ||
           currentState == DeviceState::FIREBASE_CONNECTING ||
           currentState == DeviceState::TIME_SYNC ||
           currentState == DeviceState::DEVICE_CLAIMING ||
           currentState == DeviceState::CAPABILITY_DETECT ||
           currentState == DeviceState::CONFIG_LOADING;
}

bool StateMachine::isRunning() const {
    return currentState == DeviceState::RUNNING;
}

bool StateMachine::isOffline() const {
    return currentState == DeviceState::OFFLINE_RUNNING;
}

void StateMachine::setError(const char* error) {
    strncpy(lastError, error, sizeof(lastError) - 1);
    lastError[sizeof(lastError) - 1] = '\0';
    Serial.print("[FSM] Error: ");
    Serial.println(error);
}

void StateMachine::clearError() {
    lastError[0] = '\0';
}

const char* StateMachine::stateToString(DeviceState state) const {
    switch (state) {
        case DeviceState::BOOT: return "BOOT";
        case DeviceState::LOAD_NVS: return "LOAD_NVS";
        case DeviceState::PROVISIONING_BLE: return "PROVISIONING_BLE";
        case DeviceState::WIFI_CONNECTING: return "WIFI_CONNECTING";
        case DeviceState::TIME_SYNC: return "TIME_SYNC";
        case DeviceState::FIREBASE_CONNECTING: return "FIREBASE_CONNECTING";
        case DeviceState::DEVICE_CLAIMING: return "DEVICE_CLAIMING";
        case DeviceState::CAPABILITY_DETECT: return "CAPABILITY_DETECT";
        case DeviceState::CONFIG_LOADING: return "CONFIG_LOADING";
        case DeviceState::RUNNING: return "RUNNING";
        case DeviceState::OFFLINE_RUNNING: return "OFFLINE_RUNNING";
        case DeviceState::ERROR_RECOVERY: return "ERROR_RECOVERY";
        default: return "UNKNOWN";
    }
}
