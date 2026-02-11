# TwinGlow ESP32 Firmware

Complete firmware for the TwinGlow ESP32 device driving a 16×16 NeoPixel matrix.

## Project Structure

```
device/
├── TwinGlow.ino              # Main entry point
├── Config.h                  # Configuration constants
├── core/
│   ├── StateMachine.h/.cpp   # Global FSM
│   └── Scheduler.h/.cpp     # Periodic task scheduler
├── storage/
│   └── NvsStore.h/.cpp      # Persistent storage
├── net/
│   ├── BleProvisioning.h/.cpp # BLE GATT server
│   └── WifiManager.h/.cpp   # Wi-Fi connection manager
├── firebase/
│   ├── FirebaseClientWrap.h/.cpp # Firebase initialization
│   ├── FirestoreRepo.h/.cpp # Firestore operations
│   ├── RtdbRepo.h/.cpp      # RTDB operations
│   └── TimeSync.h/.cpp      # NTP time sync
├── ui/
│   ├── MatrixDriver.h/.cpp  # NeoPixel driver
│   ├── RenderClock.h/.cpp   # Clock renderer
│   ├── RenderSensor.h/.cpp  # Sensor renderer
│   ├── RenderAsset.h/.cpp   # Asset renderer
│   ├── AssetCache.h/.cpp    # Asset cache
│   └── ScreenPlaylist.h/.cpp # Screen playlist
├── input/
│   ├── Buttons.h/.cpp       # Button handler
│   └── ButtonActions.h/.cpp # Button actions
└── sensors/
    └── Bme680Driver.h/.cpp  # BME680 sensor driver
```

## Configuration

Before compiling, edit `Config.h` and set:

1. **Firebase Configuration** (REQUIRED):
   - `FIREBASE_API_KEY` - From Firebase Console > Project Settings > General
   - `FIREBASE_DATABASE_URL` - From Firebase Console > Realtime Database
   - `FIREBASE_DATABASE_SECRET` - From Firebase Console > Project Settings > Service Accounts > Database secrets
   - `FIREBASE_PROJECT_ID` - Your Firebase project ID

2. **Hardware Pins** (adjust if needed):
   - `NEOPIXEL_PIN` - Data pin for NeoPixel matrix (default: 2)
   - Button pins (defaults: 4, 5, 18, 19, 21)
   - BME680 I2C pins (defaults: 22, 23)

## Libraries Required

Install via Arduino Library Manager:

- **FirebaseClient** by mobizt (https://github.com/mobizt/FirebaseClient)
- **Adafruit NeoPixel** by Adafruit
- **BME680** by Zanduino (https://github.com/Zanduino/BME680)

ESP32 core libraries (built-in):
- WiFi
- BLE
- Preferences

## Compilation

1. Open `TwinGlow.ino` in Arduino IDE
2. Select your ESP32 board (Tools > Board)
3. Set partition scheme if needed (Tools > Partition Scheme)
4. Compile and upload

## Device Flow

1. **Boot** → Initialize hardware
2. **Load NVS** → Load stored credentials
3. **BLE Provisioning** (if not provisioned) → Accept Wi-Fi credentials via BLE
4. **Wi-Fi Connecting** → Connect to Wi-Fi with retry/backoff
5. **Time Sync** → Sync time via NTP
6. **Firebase Connecting** → Initialize Firebase client
7. **Device Claiming** → Create device doc and user membership
8. **Capability Detect** → Detect BME680 sensor
9. **Config Loading** → Load screens and assets from Firestore
10. **Running** → Render screens, handle buttons, periodic syncs

## Features

- **BLE Provisioning**: Wi-Fi credentials via BLE GATT service
- **Wi-Fi Management**: Automatic reconnection with exponential backoff
- **Firebase Integration**: Firestore for config, RTDB for presence/telemetry
- **Screen Rendering**: CLOCK, SENSOR, IMAGE, ANIMATION screens
- **Button Control**: 5-button interface with debouncing
- **Offline Mode**: Continues running with cached data when offline
- **Non-blocking**: All operations use millis()-based timing

## Troubleshooting

See `Config.h` for troubleshooting section with common issues and solutions.

## Notes

- Device ID is generated once and stored in NVS
- Brightness persists across reboots
- Factory reset: Very long press (~10s) on ACTION button
- BLE provisioning mode: Entered automatically if Wi-Fi fails repeatedly
