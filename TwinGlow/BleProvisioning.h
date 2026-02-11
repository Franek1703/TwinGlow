#ifndef BLE_PROVISIONING_H
#define BLE_PROVISIONING_H

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Arduino.h>
#include "Config.h"

/**
 * BLE GATT server for device provisioning
 * Accepts Wi-Fi credentials and user UID via BLE characteristics
 */
class BleProvisioning {
public:
    BleProvisioning();
    ~BleProvisioning();
    
    bool begin();
    void stop();
    
    // Check if provisioning data is complete
    bool isProvisioningComplete();
    
    // Get received data
    String getSsid() const { return ssid; }
    String getPass() const { return pass; }
    String getUid() const { return uid; }
    
    // Clear received data
    void clearData();
    
    // Status
    bool isConnected() const { return deviceConnected; }
    bool isAdvertising() const { return advertising; }
    
    // Call this in loop() to handle disconnects
    void update();
    
private:
    BLEServer* pServer;
    BLEService* pService;
    BLECharacteristic* pCharSsid;
    BLECharacteristic* pCharPass;
    BLECharacteristic* pCharUid;
    
    String ssid;
    String pass;
    String uid;
    
    bool deviceConnected;
    bool advertising;
    bool oldDeviceConnected;
    
    // Callback classes
    class ServerCallbacks;
    class CharacteristicCallbacks;
    
    void startAdvertising();
    void handleDisconnect();
};

#endif // BLE_PROVISIONING_H
