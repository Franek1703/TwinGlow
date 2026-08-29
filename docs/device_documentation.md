# Device Architecture & Firmware Flow (ESP32)

This document describes the **embedded-side architecture and runtime flow** of the TwinGlow device, powered by **ESP32**, including Wi-Fi provisioning via **Bluetooth Low Energy (BLE)**, persistent storage, Firebase integration, device claiming, sensor detection, time synchronization (NTP), and display rendering.

---

## 1. Device Responsibilities (High-Level)

The TwinGlow device is responsible for:

- Wi-Fi provisioning via BLE
- Secure storage of credentials and identifiers
- Automatic device registration and user assignment
- Fetching configuration and content from Firebase
- Rendering screens on a 16×16 LED matrix
- Optional sensor data acquisition (BME680)
- Maintaining accurate local time (NTP sync)
- Autonomous runtime behavior (offline-capable after sync)

The device firmware is designed to be **generic and cloud-driven**, with minimal hardcoded content.

---

## 2. Hardware Overview

- **Microcontroller:** ESP32
- **Display:** 16×16 RGB LED matrix (NeoPixel / WS2812)
- **Sensor (optional):** BME680 (temperature, humidity, pressure, gas)
- **Connectivity:**
    - Wi-Fi (primary backend communication)
    - Bluetooth Low Energy (initial provisioning)

---

## 3. Libraries Used

### 3.1 Bluetooth Low Energy

- ESP32 Arduino BLE library
    
    https://github.com/espressif/arduino-esp32/tree/master/libraries/BLE
    

Used for:

- Initial device provisioning
- Secure transfer of Wi-Fi credentials
- User identification during device claiming

### 3.2 Firebase Communication

- Firebase Client (mobizt)
    
    [https://github.com/mobizt/FirebaseClient](https://github.com/mobizt/FirebaseClient?utm_source=chatgpt.com)
    

Used for:

- Firestore access (screens, shared screens, assets, devices)
- Realtime Database access (presence, telemetry, commands)
- NTP time helper used to set time for the Firebase app

### 3.3 LED Matrix

- Adafruit NeoPixel
    
    https://github.com/adafruit/Adafruit_NeoPixel
    

Used for:

- Rendering pixel data on the 16×16 LED matrix
- Displaying static images, animations, and generated screens

### 3.4 Environmental Sensor

- BME680 Arduino Library
    
    [https://github.com/Zanduino/BME680](https://github.com/Zanduino/BME680?utm_source=chatgpt.com)
    

Used for:

- Detecting sensor presence
- Reading environmental data (if available)

---

## 4. Persistent Storage (NVS)

The ESP32 uses **NVS (Non-Volatile Storage)** via the Arduino `Preferences` API.

### Stored Data

- Wi-Fi SSID
- Wi-Fi password
- Generated `deviceId`
- Provisioning status flag

All data survives reboot/power loss.

---

## 5. Device Identity

### 5.1 Device ID Generation

- On first boot, the device generates a **random UUID** (`deviceId`)
- The ID is stored permanently in NVS
- This `deviceId` is used as:
    - Firestore `/devices/{deviceId}`
    - Realtime Database paths
    - Internal device identity

---

## 6. BLE Provisioning & Device Claiming

### 6.1 When BLE Provisioning Starts

BLE provisioning mode is entered when:

- No Wi-Fi credentials are stored in NVS
- OR Wi-Fi connection fails repeatedly

### 6.2 BLE GATT Service

The device exposes a custom BLE service with characteristics for:

- Wi-Fi SSID
- Wi-Fi password
- Firebase User ID (`uid`)
- Provisioning command / confirmation

### 6.3 Provisioning Flow

1. User opens the TwinGlow mobile app
2. App scans for nearby TwinGlow devices over BLE
3. User selects a device
4. App sends:
    - Wi-Fi SSID
    - Wi-Fi password
    - Logged-in Firebase `uid`
5. Device stores credentials and `uid` in NVS
6. Device disconnects BLE and reboots (or continues)

---

## 7. Wi-Fi Connection

1. Device loads SSID and password from NVS
2. Attempts to connect to Wi-Fi
3. If connection succeeds → provisioning ends
4. If connection fails → re-enters BLE provisioning mode

---

## 8. Firebase Connection & Device Claiming

### 8.1 Firebase Authentication

- Device connects to Firebase using application credentials
- Communication is performed via REST (Firestore + RTDB)

### 8.2 Device Registration / Claiming

1. Device checks if `/devices/{deviceId}` exists
2. If not, device creates `/devices/{deviceId}` metadata
3. Using the `uid` received during provisioning:
    - Create `/users/{uid}/devices/{deviceId}` membership doc
    - Device becomes visible in the app automatically

---

## 9. Hardware Capability Detection (BME680)

### 9.1 Sensor Detection

- On boot, the device attempts to initialize the BME680
- Presence is detected automatically

### 9.2 Capability Update Logic

- Read current capability state from Firestore
- If detected differs from stored:
    - Update `/devices/{deviceId}.hw.bme680`
- Do nothing if unchanged (avoid extra writes)

---

## 10. Configuration Loading from Firestore

### 10.1 Config Versioning

- Device reads `/devices/{deviceId}.configVersion`
- This value is polled every 60 s (Firestore listening is not supported via REST).
- A 5 s RTDB doorbell read of `/config/{deviceId}/configVersion` exists to avoid
  waiting out that minute, but is **disabled** (`ENABLE_RTDB_DOORBELL 0`): it
  wedged the shared TLS client on hardware. So 60 s is the real latency today.
- If `configVersion` changes → reload config + assets

### 10.2 Data Loaded

On reload, the device fetches:

1. `/devices/{deviceId}/screens` (device-local playlist)
2. Shared screen docs if referenced by pairing/shared model (per your Firebase schema)
3. `/assets/{assetId}` pixel data

All data is cached locally in RAM (optional flash caching later).

---

## 10.3 Time Synchronization (NTP) for CLOCK Screen

ESP32 has no battery-backed RTC, so time is obtained via **NTP** after Wi-Fi connects.

### 10.3.1 Library mechanism

The FirebaseClient examples use an NTP helper `get_ntp_time()` and apply it to the Firebase app via:

- `app.setTime(get_ntp_time());`

This sets the internal time context used by the Firebase client (important for TLS/auth flows).

### 10.3.2 Sync schedule (every 6 hours)

**Policy:**

- Sync on boot (immediately after Wi-Fi connects)
- Re-sync every **6 hours**
- If NTP fails, keep last known time and try again later

**Recommended behavior:**

- Store `lastNtpSyncMs` in RAM (optionally also in NVS if you want reboot persistence)
- Every main loop tick (or a dedicated timer/task), check if `millis() - lastNtpSyncMs >= 6h`
- If yes and Wi-Fi is connected:
    - call `app.setTime(get_ntp_time());`
    - update `lastNtpSyncMs`

### 10.3.3 Offline behavior

If offline:

- CLOCK continues running based on local system time (will drift slightly)
- Next successful Wi-Fi period triggers re-sync

---

## 11. Runtime Behavior

### 11.1 Screen Scheduler

- Device runs a local screen playlist
- Screen order/duration are device-specific
- No backend dependency during normal operation

### 11.2 Screen Rendering (16×16)

TwinGlow supports both:

- **Asset-driven screens** (IMAGE, ANIMATION) → rendered from cached Firestore assets
- **Procedural screens** (CLOCK, SENSOR) → generated locally on ESP32 using config from Firestore

### 11.2.1 CLOCK (procedural, local)

- Uses locally synchronized time (NTP boot + periodic every 6h)
- Firebase provides **presentation config only**, e.g.:
    - `format` (12H/24H)
    - `layout` (e.g., `HHMM_PLUS_SECONDS_BAR`)
    - `fgColor`, `accentColor`, `bgColor`, `brightness`
- No pixels are stored in Firebase for CLOCK

### 11.2.2 SENSOR / BME680 (procedural, local)

- Reads BME680 locally
- Firebase provides **presentation config only**, e.g.:
    - `mode` (single / auto-cycle)
    - `show` metrics (temp/humidity/pressure)
    - `units`
    - `fgColor`, `accentColor`, `bgColor`, `brightness`
- Optionally mirrors current readings to RTDB telemetry for the mobile app (see §12)

### 11.3 Offline Behavior

If Wi-Fi or Firebase becomes unavailable:

- Device continues operating using cached configuration/assets
- CLOCK continues using local time (may drift slightly until next NTP sync)
- SENSOR continues reading locally (if hardware present)

---

## 12. Realtime Database Usage

RTDB is used only for **live and transient data**.

**Paths:**
- `/presence/{deviceId}` – heartbeat (updated every 20 seconds)
- `/telemetry/{deviceId}` – sensor readings (optional, updated every 10 seconds if BME680 present)
- `/config/{deviceId}/configVersion` – config-change doorbell, written by the app; device-side read is currently disabled
- `/commands/{deviceId}` – runtime commands (dead code: `RtdbRepo::checkCommands()`
  exists but has no call site, and the app never writes the node)

**Implementation:**
- Fields are set individually using nested paths to avoid JSON parsing issues
- Presence updates include `online` (boolean) and `lastSeenMs` (epoch milliseconds)
- Telemetry includes `temperatureC`, `humidityPct`, `pressureHPa`, `gasOhms`, `updatedMs`
- All updates check Wi-Fi connectivity and log errors
- Failed updates don't block device operation

---

## 13. Reliability Notes (NeoPixel + Wi-Fi)

- NeoPixel timing is sensitive to Wi-Fi interrupts
- Rendering should:
    - limit FPS
    - avoid long blocking sections
    - isolate rendering from network operations

---

## 14. Firmware Flow Summary

1. Boot
2. Load credentials and `deviceId` from NVS
3. If Wi-Fi missing → BLE provisioning
4. Connect to Wi-Fi
5. **Sync time via NTP** (`app.setTime(get_ntp_time())`) and schedule re-sync every 6h
6. Connect to Firebase
7. Register / claim device
8. Detect hardware capabilities (BME680)
9. Load configuration and assets
10. Run local screen scheduler
11. Poll `configVersion` periodically and reload if changed

---

## 15. Design Principles

- Cloud-driven configuration (including colors/layout)
- Procedural screens generated locally (CLOCK/SENSOR)
- Minimal runtime writes
- Offline-first behavior
- Clear separation: layout vs content vs runtime state
- User-friendly provisioning + automatic claiming

[Physical Button Interface](https://www.notion.so/Physical-Button-Interface-303562ba02fe808ab9e8c031c7c4d8b9?pvs=21)

[Firebase Authentication & Communication (ESP32)](https://www.notion.so/Firebase-Authentication-Communication-ESP32-303562ba02fe80b9b31be7438f5f2c66?pvs=21)

[ESP32 Firmware – Code Architecture & Full Runtime Flow](https://www.notion.so/ESP32-Firmware-Code-Architecture-Full-Runtime-Flow-303562ba02fe80dc9910e251fd1e15ed?pvs=21)