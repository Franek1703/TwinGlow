#include "BleProvisioning.h"

// Server callbacks
class BleProvisioning::ServerCallbacks: public BLEServerCallbacks {
public:
    bool* deviceConnectedPtr;
    
    ServerCallbacks(bool* connected) : deviceConnectedPtr(connected) {}
    
    void onConnect(BLEServer* pServer) {
        Serial.println(F("[BLE] Client connected"));
        *deviceConnectedPtr = true;
    }
    
    void onDisconnect(BLEServer* pServer) {
        Serial.println(F("[BLE] Client disconnected"));
        *deviceConnectedPtr = false;
    }
};

// Characteristic callbacks
class BleProvisioning::CharacteristicCallbacks: public BLECharacteristicCallbacks {
public:
    String* ssidPtr;
    String* passPtr;
    String* uidPtr;
    String targetUuid;
    
    CharacteristicCallbacks(String* s, String* p, String* u, const char* uuid) 
        : ssidPtr(s), passPtr(p), uidPtr(u), targetUuid(uuid) {}
    
    void onWrite(BLECharacteristic* pCharacteristic) {
        String valueStr = pCharacteristic->getValue();
        std::string value(valueStr.c_str(), valueStr.length());
        String uuid = String(pCharacteristic->getUUID().toString().c_str());
        
        Serial.print(F("[BLE] Received write to "));
        Serial.print(uuid);
        Serial.print(F(", length: "));
        Serial.println(value.length());
        
        // Determine which characteristic was written based on target UUID
        if (targetUuid == BLE_CHAR_SSID_UUID) {
            ssidPtr->clear();
            for (size_t i = 0; i < value.length() && i < 32; i++) {
                ssidPtr->concat((char)value[i]);
            }
            Serial.print(F("[BLE] SSID: "));
            Serial.println(*ssidPtr);
        } else if (targetUuid == BLE_CHAR_PASS_UUID) {
            passPtr->clear();
            for (size_t i = 0; i < value.length() && i < 64; i++) {
                passPtr->concat((char)value[i]);
            }
            Serial.print(F("[BLE] Password received (length: "));
            Serial.print(passPtr->length());
            Serial.println(F(")"));
        } else if (targetUuid == BLE_CHAR_UID_UUID) {
            uidPtr->clear();
            for (size_t i = 0; i < value.length() && i < 128; i++) {
                uidPtr->concat((char)value[i]);
            }
            Serial.print(F("[BLE] UID: "));
            Serial.println(*uidPtr);
        }
    }
};

BleProvisioning::BleProvisioning() 
    : pServer(nullptr), pService(nullptr),
      pCharSsid(nullptr), pCharPass(nullptr), pCharUid(nullptr),
      deviceConnected(false), advertising(false), oldDeviceConnected(false) {
}

BleProvisioning::~BleProvisioning() {
    stop();
}

bool BleProvisioning::begin() {
    if (pServer != nullptr) {
        Serial.println(F("[BLE] Already initialized"));
        return true;
    }
    
    // Initialize BLE
    BLEDevice::init(BLE_DEVICE_NAME);
    
    // Create server
    pServer = BLEDevice::createServer();
    ServerCallbacks* serverCallbacks = new ServerCallbacks(&deviceConnected);
    pServer->setCallbacks(serverCallbacks);
    
    // Create service
    pService = pServer->createService(BLE_SERVICE_UUID);
    
    // Create SSID characteristic
    pCharSsid = pService->createCharacteristic(
        BLE_CHAR_SSID_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharSsid->setCallbacks(new CharacteristicCallbacks(&ssid, &pass, &uid, BLE_CHAR_SSID_UUID));
    
    // Create Password characteristic
    pCharPass = pService->createCharacteristic(
        BLE_CHAR_PASS_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharPass->setCallbacks(new CharacteristicCallbacks(&ssid, &pass, &uid, BLE_CHAR_PASS_UUID));
    
    // Create UID characteristic
    pCharUid = pService->createCharacteristic(
        BLE_CHAR_UID_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharUid->setCallbacks(new CharacteristicCallbacks(&ssid, &pass, &uid, BLE_CHAR_UID_UUID));
    
    // Start service
    pService->start();
    
    // Start advertising
    startAdvertising();
    
    Serial.println(F("[BLE] Provisioning service started"));
    return true;
}

void BleProvisioning::startAdvertising() {
    if (pServer == nullptr) return;
    
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // helps with iPhone connections issue
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
    
    advertising = true;
    Serial.println(F("[BLE] Advertising started"));
}

void BleProvisioning::stop() {
    if (pServer != nullptr) {
        BLEDevice::stopAdvertising();
        advertising = false;
        deviceConnected = false;
        Serial.println(F("[BLE] Stopped"));
    }
}

bool BleProvisioning::isProvisioningComplete() {
    return ssid.length() > 0 && uid.length() > 0;
    // Password can be empty for open networks
}

void BleProvisioning::clearData() {
    ssid = "";
    pass = "";
    uid = "";
}

void BleProvisioning::update() {
    if (!deviceConnected && oldDeviceConnected) {
        // Client disconnected
        delay(500); // Give Bluetooth stack time
        if (isProvisioningComplete()) {
            Serial.println(F("[BLE] Provisioning complete, stopping BLE"));
            stop();
        } else {
            Serial.println(F("[BLE] Incomplete provisioning data, keeping BLE active"));
            clearData();
        }
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        // Client connected
        oldDeviceConnected = deviceConnected;
    }
}
