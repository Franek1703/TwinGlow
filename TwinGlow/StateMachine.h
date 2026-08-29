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

    // Returns true exactly once per state entry, then clears itself.
    // Handlers use this instead of a permanent `static bool` guard, so a state
    // that is entered a second time (e.g. CONFIG_LOADING after a config change)
    // runs its body again instead of silently doing nothing.
    bool justEntered();

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
    bool entryPending;
    char lastError[64];
    
    const char* stateToString(DeviceState state) const;
};

#endif // STATE_MACHINE_H
