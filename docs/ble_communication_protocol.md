# BLE Communication Protocol Documentation

This document describes the Bluetooth Low Energy (BLE) communication protocol between the TwinGlow mobile application and ESP32 devices.

---

## Table of Contents

1. [Overview](#overview)
2. [BLE Service Architecture](#ble-service-architecture)
3. [Service and Characteristic UUIDs](#service-and-characteristic-uuids)
4. [Provisioning Flow](#provisioning-flow)
5. [Data Formats](#data-formats)
6. [Error Handling](#error-handling)
7. [Security Considerations](#security-considerations)
8. [Implementation Details](#implementation-details)

---

## Overview

BLE is used **exclusively during device provisioning**. Once a device is provisioned with Wi-Fi credentials and connected to Firebase, all further communication happens over the internet via Firebase services.

### Purpose

- Initial device setup and configuration
- Wi-Fi credential transfer
- User ID association
- Device claiming

### When BLE is Active

BLE provisioning mode is entered when:
- Device has no Wi-Fi credentials stored in NVS
- Wi-Fi connection fails repeatedly
- Device is factory reset

---

## BLE Service Architecture

The ESP32 device exposes a custom BLE GATT service with characteristics for provisioning data.

### Service Structure

```
TwinGlow Provisioning Service (0000ff00-0000-1000-8000-00805f9b34fb)
├── SSID Characteristic (0000ff01-0000-1000-8000-00805f9b34fb)
├── Password Characteristic (0000ff02-0000-1000-8000-00805f9b34fb)
└── User ID Characteristic (0000ff03-0000-1000-8000-00805f9b34fb)
```

---

## Service and Characteristic UUIDs

### Service UUID

**TwinGlow Provisioning Service**
- UUID: `0000ff00-0000-1000-8000-00805f9b34fb`
- Type: Primary Service
- Purpose: Encapsulates all provisioning characteristics

### Characteristic UUIDs

#### 1. SSID Characteristic

- **UUID**: `0000ff01-0000-1000-8000-00805f9b34fb`
- **Properties**: Write (without response)
- **Data Type**: UTF-8 String
- **Max Length**: 32 bytes
- **Purpose**: Receives Wi-Fi network name (SSID)

**Data Format:**
```
[SSID bytes as UTF-8]
Example: "MyWiFiNetwork" → [0x4D, 0x79, 0x57, 0x69, 0x46, 0x69, 0x4E, 0x65, 0x74, 0x77, 0x6F, 0x72, 0x6B]
```

#### 2. Password Characteristic

- **UUID**: `0000ff02-0000-1000-8000-00805f9b34fb`
- **Properties**: Write (without response)
- **Data Type**: UTF-8 String
- **Max Length**: 64 bytes
- **Purpose**: Receives Wi-Fi network password

**Data Format:**
```
[Password bytes as UTF-8]
Example: "MySecurePassword123" → [0x4D, 0x79, 0x53, ...]
```

#### 3. User ID Characteristic

- **UUID**: `0000ff03-0000-1000-8000-00805f9b34fb`
- **Properties**: Write (without response)
- **Data Type**: UTF-8 String
- **Max Length**: 128 bytes
- **Purpose**: Receives Firebase User ID (UID) to associate device with user account

**Data Format:**
```
[Firebase UID bytes as UTF-8]
Example: "abc123xyz456" → [0x61, 0x62, 0x63, 0x31, 0x32, 0x33, ...]
```

---

## Provisioning Flow

### High-Level Flow

```
Mobile App                    ESP32 Device
     |                              |
     |--[1. Scan for devices]------>|
     |<--[2. Device advertisement]--|
     |                              |
     |--[3. Connect via BLE]------->|
     |<--[4. Connection established]-|
     |                              |
     |--[5. Discover services]----->|
     |<--[6. Service list]----------|
     |                              |
     |--[7. Write SSID]------------->|
     |                              |
     |--[8. Write Password]--------->|
     |                              |
     |--[9. Write User ID]--------->|
     |                              |
     |--[10. Disconnect]----------->|
     |                              |
     |                              |--[11. Store in NVS]
     |                              |--[12. Reboot]
     |                              |--[13. Connect to Wi-Fi]
     |                              |--[14. Connect to Firebase]
```

### Detailed Step-by-Step Process

#### Step 1: Device Discovery

**Mobile App:**
1. Request Bluetooth permissions
2. Check Bluetooth adapter state
3. Start BLE scan with service UUID filter: `0000ff00-0000-1000-8000-00805f9b34fb`
4. Scan duration: 10 seconds
5. Filter devices by:
   - Service UUID in advertisement data
   - Device name containing "TwinGlow" (optional)

**ESP32 Device:**
- Advertises TwinGlow Provisioning Service UUID
- Includes device name in advertisement
- Includes RSSI signal strength

**Response:**
- List of `BLEDevice` objects with:
  - Device ID (MAC address)
  - Device name
  - RSSI value

#### Step 2: Device Selection

**Mobile App:**
- User selects device from scanned list
- App stores selected device ID

#### Step 3: Connection

**Mobile App:**
1. Connect to selected device
2. Connection timeout: 15 seconds
3. Auto-connect: false

**ESP32 Device:**
- Accepts connection
- Maintains connection state

#### Step 4: Service Discovery

**Mobile App:**
1. Discover all services on connected device
2. Locate TwinGlow Provisioning Service (`0000ff00-0000-1000-8000-00805f9b34fb`)
3. Discover characteristics within service
4. Verify all three characteristics exist:
   - SSID characteristic
   - Password characteristic
   - User ID characteristic

**ESP32 Device:**
- Exposes service and characteristics
- Responds to service discovery requests

#### Step 5: Write SSID

**Mobile App:**
1. Convert SSID string to UTF-8 bytes
2. Write to SSID characteristic (`0000ff01-0000-1000-8000-00805f9b34fb`)
3. Write mode: without response
4. Wait 200ms before next write

**ESP32 Device:**
- Receives SSID bytes
- Validates length (max 32 bytes)
- Stores temporarily in memory

**Error Handling:**
- If write fails: Disconnect and throw error
- If length exceeds 32 bytes: Truncate or reject

#### Step 6: Write Password

**Mobile App:**
1. Convert password string to UTF-8 bytes
2. Write to Password characteristic (`0000ff02-0000-1000-8000-00805f9b34fb`)
3. Write mode: without response
4. Wait 200ms before next write

**ESP32 Device:**
- Receives password bytes
- Validates length (max 64 bytes)
- Stores temporarily in memory

**Error Handling:**
- If write fails: Disconnect and throw error
- If length exceeds 64 bytes: Truncate or reject

#### Step 7: Write User ID

**Mobile App:**
1. Get current authenticated Firebase user ID
2. Convert UID string to UTF-8 bytes
3. Write to User ID characteristic (`0000ff03-0000-1000-8000-00805f9b34fb`)
4. Write mode: without response
5. Wait 500ms before disconnecting

**ESP32 Device:**
- Receives user ID bytes
- Validates length (max 128 bytes)
- Stores temporarily in memory

**Error Handling:**
- If write fails: Disconnect and throw error
- If length exceeds 128 bytes: Truncate or reject

#### Step 8: Disconnection

**Mobile App:**
1. Disconnect from device
2. Clean up BLE resources
3. Show success message to user

**ESP32 Device:**
1. On disconnect, validate all three values received
2. Store credentials in NVS (Non-Volatile Storage):
   - Wi-Fi SSID
   - Wi-Fi Password
   - Firebase User ID
3. Set provisioning flag in NVS
4. Reboot device (or transition to Wi-Fi connection state)

#### Step 9: Post-Provisioning (ESP32)

**ESP32 Device:**
1. Load credentials from NVS
2. Attempt Wi-Fi connection
3. If successful:
   - Connect to Firebase
   - Create device document in Firestore
   - Start normal operation
4. If failed:
   - Return to BLE provisioning mode
   - Clear invalid credentials

---

## Data Formats

### SSID Format

- **Type**: UTF-8 encoded string
- **Length**: 1-32 bytes
- **Validation**: 
  - Non-empty
  - Valid UTF-8 encoding
  - No null terminators required

**Example:**
```
Input: "MyWiFi"
Bytes: [0x4D, 0x79, 0x57, 0x69, 0x46, 0x69]
```

### Password Format

- **Type**: UTF-8 encoded string
- **Length**: 0-64 bytes (empty password for open networks)
- **Validation**:
  - Valid UTF-8 encoding
  - No null terminators required

**Example:**
```
Input: "SecurePass123!"
Bytes: [0x53, 0x65, 0x63, 0x75, 0x72, 0x65, 0x50, 0x61, 0x73, 0x73, 0x31, 0x32, 0x33, 0x21]
```

### User ID Format

- **Type**: UTF-8 encoded string
- **Length**: 1-128 bytes
- **Format**: Firebase Authentication UID
- **Validation**:
  - Non-empty
  - Valid UTF-8 encoding
  - Matches Firebase UID format

**Example:**
```
Input: "abc123xyz456def789"
Bytes: [0x61, 0x62, 0x63, 0x31, 0x32, 0x33, 0x78, 0x79, 0x7A, 0x34, 0x35, 0x36, 0x64, 0x65, 0x66, 0x37, 0x38, 0x39]
```

---

## Error Handling

### Mobile App Error Scenarios

#### Bluetooth Not Supported
- **Error**: `Bluetooth is not supported on this device`
- **Action**: Show error message, disable BLE features

#### Bluetooth Not Enabled
- **Error**: `Bluetooth is not enabled`
- **Action**: Prompt user to enable Bluetooth, attempt to turn on (Android only)

#### Device Not Found
- **Error**: `Device not found: {deviceId}`
- **Action**: Retry scan, show error message

#### Connection Timeout
- **Error**: Connection timeout after 15 seconds
- **Action**: Retry connection, show error message

#### Service Not Found
- **Error**: `TwinGlow service not found`
- **Action**: Verify device is TwinGlow device, retry connection

#### Characteristic Not Found
- **Error**: `{Characteristic} characteristic not found`
- **Action**: Verify device firmware version, show error message

#### Write Failure
- **Error**: `Failed to write {data type}`
- **Action**: Retry write operation, disconnect and show error

#### Provisioning Failure
- **Error**: `Failed to provision device: {reason}`
- **Action**: Disconnect, show error message, allow retry

### ESP32 Device Error Scenarios

#### Invalid SSID Length
- **Action**: Reject write, maintain connection for retry

#### Invalid Password Length
- **Action**: Reject write, maintain connection for retry

#### Invalid User ID Format
- **Action**: Reject write, maintain connection for retry

#### Missing Data on Disconnect
- **Action**: Clear partial data, remain in provisioning mode

#### NVS Write Failure
- **Action**: Retry NVS write, if persistent failure, remain in provisioning mode

---

## Security Considerations

### BLE Security

1. **No Encryption**: BLE provisioning does not use encryption
   - Wi-Fi credentials are transmitted in plaintext
   - User ID is transmitted in plaintext
   - **Mitigation**: BLE range is limited (~10 meters), physical proximity required

2. **Pairing Not Required**: No BLE pairing/bonding
   - Faster provisioning flow
   - Less secure but acceptable for one-time setup

3. **Service UUID Filtering**: Only devices advertising TwinGlow service are discovered
   - Reduces attack surface
   - Prevents connection to unauthorized devices

### Best Practices

1. **Physical Security**: Ensure physical proximity during provisioning
   - User should be near device
   - Avoid provisioning in public spaces

2. **One-Time Use**: BLE provisioning is one-time only
   - After successful Wi-Fi connection, device no longer advertises BLE service
   - To reprovision: Factory reset device

3. **Credential Validation**: ESP32 validates received credentials
   - Length checks
   - Format validation
   - Storage verification

4. **Timeout Handling**: All operations have timeouts
   - Connection timeout: 15 seconds
   - Write timeout: Per BLE stack defaults
   - Prevents hanging connections

---

## Implementation Details

### Mobile App Implementation

**File**: `lib/services/ble/ble_repository_impl.dart`

**Key Methods:**
- `requestPermissions()`: Request Bluetooth and location permissions
- `scanForDevices()`: Scan for TwinGlow devices
- `connect(String deviceId)`: Connect to device
- `disconnect()`: Disconnect from device
- `provisionDevice()`: Complete provisioning flow

**Dependencies:**
- `flutter_blue_plus: ^2.1.0`
- License: `License.free` for development

**Service UUIDs:**
```dart
const String twinGlowServiceUUID = '0000ff00-0000-1000-8000-00805f9b34fb';
const String ssidCharacteristicUUID = '0000ff01-0000-1000-8000-00805f9b34fb';
const String passwordCharacteristicUUID = '0000ff02-0000-1000-8000-00805f9b34fb';
const String userIdCharacteristicUUID = '0000ff03-0000-1000-8000-00805f9b34fb';
```

### ESP32 Device Implementation

**Requirements:**
- BLE GATT server implementation
- Service and characteristic definitions matching UUIDs above
- NVS storage for credentials
- State machine for provisioning flow

**Expected Behavior:**
1. Advertise provisioning service when in provisioning mode
2. Accept connections and service discovery
3. Accept writes to all three characteristics
4. Store credentials in NVS on disconnect
5. Reboot or transition to Wi-Fi connection state

---

## Testing and Validation

### Test Scenarios

1. **Successful Provisioning**
   - Scan finds device
   - Connection succeeds
   - All three writes succeed
   - Device stores credentials and connects to Wi-Fi

2. **Connection Failure**
   - Device out of range
   - Device already connected to another client
   - Device firmware error

3. **Write Failure**
   - Invalid data format
   - Characteristic not found
   - Write timeout

4. **Partial Provisioning**
   - Connection drops after SSID write
   - Connection drops after password write
   - Device should reject incomplete data

5. **Invalid Data**
   - SSID too long (>32 bytes)
   - Password too long (>64 bytes)
   - User ID too long (>128 bytes)
   - Invalid UTF-8 encoding

---

## Future Enhancements

### Potential Improvements

1. **Encryption**: Add BLE encryption for credential transfer
2. **Acknowledgment**: Add acknowledgment characteristic for write confirmation
3. **Status Characteristic**: Add status characteristic for provisioning progress
4. **Error Codes**: Standardize error codes for better error handling
5. **Retry Logic**: Implement automatic retry for failed writes
6. **Provisioning Timeout**: Add overall provisioning timeout (e.g., 60 seconds)

---

## References

- [Mobile App Backend Documentation](./mobile_app_backend_doc.md)
- [Device Documentation](./device_documentation.md)
- [Device Code Architecture](./device_code_architecture.md)
- [Flutter Blue Plus Documentation](https://pub.dev/packages/flutter_blue_plus)

---

## Revision History

- **v1.0** (Initial): Basic provisioning flow with SSID, password, and user ID
- Future revisions will document enhancements and protocol changes
