#ifndef STATE_MACHINE_H
#define STATE_MACHINE_H

/**
 * Global device state machine
 * Controls device lifecycle from boot to running
 */
enum class DeviceState {
    BOOT,
    LOAD_NVS,
    PROVISIONING_BLE,
    WIFI_CONNECTING,
    TIME_SYNC,
    FIREBASE_CONNECTING,
    DEVICE_CLAIMING,
    CAPABILITY_DETECT,
    CONFIG_LOADING,
    RUNNING,
    OFFLINE_RUNNING,
    ERROR_RECOVERY
};

class StateMachine {
public:
    StateMachine();
    
    DeviceState getState() const { return currentState; }
    const char* getStateName() const;
    
    void setState(DeviceState newState);
    void transition(DeviceState newState);
    
    // State check helpers
    bool isProvisioning() const;
    bool isConnecting() const;
    bool isRunning() const;
    bool isOffline() const;
    
    // Error handling
    void setError(const char* error);
    const char* getError() const { return lastError; }
    void clearError();
    
private:
    DeviceState currentState;
    char lastError[128];
    
    const char* stateToString(DeviceState state) const;
};

#endif // STATE_MACHINE_H
