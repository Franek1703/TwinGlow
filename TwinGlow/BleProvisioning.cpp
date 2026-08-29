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
      pServerCallbacks(nullptr), pSsidCallbacks(nullptr),
      pPassCallbacks(nullptr), pUidCallbacks(nullptr),
      stackReleased(false),
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
    if (stackReleased) {
        // stop() released the controller memory; it cannot be reclaimed
        // without a reboot.
        Serial.println(F("[BLE] Stack already released this boot, reboot to re-provision"));
        return false;
    }

    // Initialize BLE
    BLEDevice::init(BLE_DEVICE_NAME);

    // Create server
    pServer = BLEDevice::createServer();
    pServerCallbacks = new ServerCallbacks(&deviceConnected);
    pServer->setCallbacks(pServerCallbacks);

    // Create service
    pService = pServer->createService(BLE_SERVICE_UUID);

    // Create SSID characteristic
    pCharSsid = pService->createCharacteristic(
        BLE_CHAR_SSID_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pSsidCallbacks = new CharacteristicCallbacks(&ssid, &pass, &uid, BLE_CHAR_SSID_UUID);
    pCharSsid->setCallbacks(pSsidCallbacks);

    // Create Password characteristic
    pCharPass = pService->createCharacteristic(
        BLE_CHAR_PASS_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pPassCallbacks = new CharacteristicCallbacks(&ssid, &pass, &uid, BLE_CHAR_PASS_UUID);
    pCharPass->setCallbacks(pPassCallbacks);

    // Create UID characteristic
    pCharUid = pService->createCharacteristic(
        BLE_CHAR_UID_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pUidCallbacks = new CharacteristicCallbacks(&ssid, &pass, &uid, BLE_CHAR_UID_UUID);
    pCharUid->setCallbacks(pUidCallbacks);

    // Start service
    pService->start();

    // Start advertising
    startAdvertising();

    Serial.print(F("[BLE] Provisioning service started, free heap="));
    Serial.println(ESP.getFreeHeap());
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
    if (pServer == nullptr) return;

    uint32_t heapBefore = ESP.getFreeHeap();

    BLEDevice::stopAdvertising();
    advertising = false;
    deviceConnected = false;

    // Stopping advertising alone leaves the BT controller and Bluedroid host
    // resident, holding tens of KB of heap for the rest of the session - which
    // then has to cover Wi-Fi, TLS and multi-KB Firestore responses.
    // deinit(true) also releases the controller memory permanently for this boot.
    // It deletes the server (and with it the service and characteristics), so
    // every pointer into that tree must be dropped here.
    BLEDevice::deinit(true);
    stackReleased = true;

    pServer = nullptr;
    pService = nullptr;
    pCharSsid = nullptr;
    pCharPass = nullptr;
    pCharUid = nullptr;

    // The BLE objects never owned these.
    delete pServerCallbacks;
    pServerCallbacks = nullptr;
    delete pSsidCallbacks;
    pSsidCallbacks = nullptr;
    delete pPassCallbacks;
    pPassCallbacks = nullptr;
    delete pUidCallbacks;
    pUidCallbacks = nullptr;

    Serial.print(F("[BLE] Stopped and stack released, heap "));
    Serial.print(heapBefore);
    Serial.print(F(" -> "));
    Serial.print(ESP.getFreeHeap());
    Serial.print(F(" (reclaimed "));
    Serial.print((int32_t)ESP.getFreeHeap() - (int32_t)heapBefore);
    Serial.println(F(" bytes)"));
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
