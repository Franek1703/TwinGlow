#TwinGlow – System Documentation

## 1. Project Overview

**TwinGlow** is an IoT-based interactive device built around a **16×16 LED pixel matrix** and powered by an **ESP32 microcontroller**.

The project enables two connected users to **share visual content and states** such as images, animations, time, sensor data, and interactive screens in real time.

The core idea of TwinGlow is to keep the device firmware **generic and reusable**, while all visual content, screen configuration, and synchronization logic are **driven dynamically from the cloud** using Firebase.

TwinGlow is designed as an emotional, personal, and extensible device rather than a single-purpose gadget.

---

## 2. Key Features

- 16×16 pixel LED matrix display
- ESP32-based embedded system
- Dedicated mobile application
- Cloud-based content and configuration
- Real-time synchronization between paired devices
- Modular screen system
- Support for:
    - Clock screen
    - Static images
    - Animations (GIF-like frame sequences)
    - Sensor data visualization (BME680)
    - Future interactive screens (e.g. simple games)

---

## 3. System Architecture Overview

TwinGlow consists of three main layers:

1. **Embedded Device (ESP32)**
2. **Cloud Backend (Firebase)**
3. **Mobile Application**

The device firmware contains:

- display rendering logic
- screen state machine
- communication layer
- cloud synchronization client

All **screens, images, animations, and screen order** are fetched dynamically from the cloud.

---

## 4. Embedded Device (ESP32)

### Responsibilities

- Connect to Wi-Fi
- Authenticate with Firebase
- Fetch screen configuration and assets
- Render content on the LED matrix
- Synchronize state with paired device
- Read sensor data (BME680)
- Switch screens based on cloud state

### Hardware Components

- ESP32 microcontroller
- 16×16 LED matrix
- BME680 environmental sensor (optional)

### Firmware Philosophy

The firmware is **content-agnostic**:

- No hardcoded images
- No hardcoded screen sequences
- Minimal default assets only for fallback

---

## 5. Screen-Based UI Model

TwinGlow operates using a **screen stack / screen playlist** concept.

Each screen:

- Has a type (clock, image, animation, sensor, game)
- Has configuration data stored in the cloud
- Can be enabled or disabled per user
- Can be shared or kept private

### Example Screen Flow

1. Clock screen
2. Image screen (heart icon)
3. Image screen (custom uploaded image)
4. Animation screen
5. Game screen (future)

The active screen and screen order are controlled remotely via the mobile app.

---

## 6. Default and Custom Content

### Default Content

- Built-in fallback icons (heart, happy face, sad face, etc.)
- Used when:
    - Cloud data is unavailable
    - User has not uploaded custom content

### Custom Content

- Images and animations uploaded via mobile app
- Stored in Firebase (Firestore + Storage)
- Dynamically loaded by ESP32

Users can:

- Add new images
- Remove images
- Replace default images
- Assign images to specific screens

---

## 7. Paired Device Concept

TwinGlow supports pairing between two users/devices.

Paired users can:

- Share selected screens
- Synchronize screen state
- Send images or animations to each other

Each screen has a **sharing flag** (`isShared`) that determines whether it is:

- Local only
- Shared with the paired user

### Where shared data lives

A screen document owns **all of its content** — including its asset pool. The pair's
`sharedScreens` collection stores only a **pointer** to which screen is shared, never the content
itself:

- `/devices/{deviceId}/screens/{screenId}` → `isShared`, `defaultAssetId`, `availableAssetIds`
- `/pairs/{pairId}/sharedScreens/{sharedScreenId}` → `deviceId`, `screenId`, `ownerUid`, `type`

This keeps multi-image screens working for users who are not paired, and gives a paired user a
single place to discover what the other person has shared.

> **Status:** pairing is not currently functional — see the known issues in the Firebase
> documentation. Screens can hold multiple images today; the sharing pointer is written only once
> a pair exists.

---

## 8. Cloud Backend (Firebase)

### Firebase Services Used

### Firestore

- User profiles
- Device metadata
- Screen definitions
- Screen configuration
- Sharing permissions
- Pairing relationships

### Realtime Database

- Current active screen
- Live screen state
- Synchronization flags

This split allows:

- Structured configuration via Firestore
- Low-latency real-time updates via RTDB

---

## 9. Mobile Application

### Responsibilities

- Device onboarding and pairing
- Screen management
- Content upload (images, animations)
- Screen order configuration
- Sharing control
- Real-time preview (future)

The mobile app acts as the **main control panel** for the TwinGlow ecosystem.

---

## 10. Design Goals

- High flexibility
- Cloud-driven behavior
- Minimal firmware updates
- Emotional and social interaction
- Easy extensibility
- Clear separation of logic and content

---

## 11. Future Extensions

- Interactive mini-games
- Touch or button input
- Sound or haptic feedback
- Multiple paired devices
- Advanced animations
- OTA firmware updates

---

## 12. Summary

TwinGlow is designed as a **modular, cloud-controlled, and socially connected LED matrix device**.

By moving content and configuration to Firebase, the system remains flexible, scalable, and easy to evolve without firmware changes.

---

[Firebase Documentation](https://www.notion.so/Firebase-Documentation-302562ba02fe80acb1cbfb895139440b?pvs=21)

[Device Architecture & Firmware Flow (ESP32)](https://www.notion.so/Device-Architecture-Firmware-Flow-ESP32-302562ba02fe80088fa1c2f0cd4ebb5a?pvs=21)

[Mobile App – Architecture & Screen Documentation](https://www.notion.so/Mobile-App-Architecture-Screen-Documentation-303562ba02fe80f6a83bcc5a6ccb892a?pvs=21)