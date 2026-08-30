# TwinGlow Mobile App – Backend Architecture

This document describes the **backend communication layer, Firebase integration strategy, BLE interaction model, and data synchronization flow** of the TwinGlow mobile application.

The mobile app acts as:

* User identity authority
* Device provisioning controller
* Configuration editor
* Shared content manager
* Firebase data orchestrator

The app does **not execute device logic** — it modifies cloud configuration that devices consume.

---

# 1. Backend Overview

## 1.1 Technology Stack

* **Firebase Authentication**
* **Cloud Firestore**
* **Firebase Realtime Database**
* **Bluetooth Low Energy (BLE)** (device provisioning only)
* **Flutter + Cubit (flutter_bloc)**

---

# 2. Backend Responsibilities of the Mobile App

The mobile app is responsible for:

1. User authentication
2. Device provisioning via BLE
3. Managing Firestore documents
4. Writing RTDB commands
5. Managing pairing and shared screens
6. Asset creation and modification
7. Device configuration editing

The device (ESP32):

* Pulls configuration
* Pushes telemetry
* Maintains presence
* Executes screen logic

---

# 3. Firebase Authentication Layer

## 3.1 Authentication Method

The mobile app uses:

* Email / Password (Firebase Auth)

The authenticated user provides:

```
uid
idToken
refreshToken
```

---

## 3.2 Role of Authentication in Backend

Authentication is required to:

* Read/write user-scoped Firestore documents
* Modify device configurations
* Create pairing relationships
* Manage assets

The app never exposes service account credentials.

---

# 4. Firestore Usage (Persistent Configuration)

Firestore stores all persistent configuration.

## 4.1 Core Collections

### `/users/{uid}`

User metadata and references:

```
users/
  {uid}
    devices/
    pairId
    preferences
```

---

### `/devices/{deviceId}`

Device-level configuration:

* name
* brightness (0-255, app-set; see §8.4)
* sleepMode (map: enabled, startMinute, endMinute, brightness)
* hardware capabilities
* configVersion
* screens/

---

### `/devices/{deviceId}/screens/{screenId}`

Screen definitions (playlist).

Includes:

* type
* order
* enabled
* duration
* config
* sharedScreenRef (optional)

---

### `/sharedScreens/{sharedScreenId}`

If screen is shared:

* Shared content configuration
* Asset references
* Owned by pairId

---

### `/assets/{assetId}`

User and default assets.

Sparse pixel storage model.

---

## 4.2 Firestore Write Strategy

Mobile app writes:

* Screen updates
* Asset changes
* Device settings
* Pairing changes

When configuration changes:

```
Increment device.configVersion
```

Device detects version change and reloads.

---

# 5. Realtime Database Usage (Live State)

RTDB is used only for **volatile and live data**.

## 5.1 Paths Used

```
presence/{deviceId}
telemetry/{deviceId}
commands/{deviceId}
```

---

## 5.2 Presence

Device writes heartbeat:

```
presence/{deviceId}
  online: true
  lastSeen: timestamp
```

App subscribes in real-time.

---

## 5.3 Telemetry

Device pushes:

```
temperature
humidity
brightness
activeScreen
```

App reads for live display only.

---

## 5.4 Commands

App writes:

```
commands/{deviceId}
  type: "refresh"
  payload: {}
```

Device listens and clears command after execution.

---

# 6. BLE Communication Layer

BLE is used only during provisioning.

## 6.1 Provisioning Payload

App sends:

```
{
  ssid,
  password,
  uid
}
```

Device stores in NVS and reboots.

---

## 6.2 Security Model

* BLE only allowed during provisioning mode
* No long-term BLE connection
* Device uses Firebase after Wi-Fi connection

---

# 7. Pairing & Shared Screens Backend Logic

Pairing is stored in:

```
pairs/{pairId}
```

Contains:

```
userA
userB
createdAt
```

---

## 7.1 Shared Screen Model

Each device screen may include:

```
sharedScreenRef: sharedScreenId
```

If present:

* Screen content lives in `/sharedScreens`
* Both users can modify it
* Device reads shared content via reference

This prevents duplication of configuration across devices.

---

# 8. Backend Flow – End-to-End Scenarios

---

## 8.1 First Device Provisioning

1. User logs in
2. App scans BLE
3. Sends Wi-Fi + uid
4. Device connects to Firebase
5. Device creates `/devices/{deviceId}`
6. Device assigns itself to `/users/{uid}/devices`
7. App listens to device list
8. Device appears in UI

---

## 8.2 Screen Update Flow

User edits screen:

1. App updates Firestore
2. App increments `devices/{deviceId}.configVersion` (`FieldValue.increment`,
   so two edits made close together cannot overwrite each other)
3. App ticks the RTDB doorbell `/config/{deviceId}/configVersion`
4. Device picks the change up on its 60 s Firestore poll. (The doorbell would
   cut this to ~5 s, but the device-side read is currently disabled - see
   ENABLE_RTDB_DOORBELL.)
5. Device reloads configuration

Step 3 is best-effort: if RTDB is unreachable the edit still succeeds and still
reaches the device, just via the slower poll.

---

## 8.3 Asset Update Flow

User edits asset:

1. Update `/assets/{assetId}`
2. Find the devices showing it and bump `configVersion` on each, ringing the
   doorbell with it. Asset writes carry no device context, so this lookup is
   what makes the flow possible at all. Since the asset pool moved onto the
   screen document a screen can reference an asset three ways, and Firestore
   cannot OR across fields, so it takes three collection-group queries whose
   results are unioned - on `assetId`, `defaultAssetId` and
   `availableAssetIds` (array-contains). Each needs its own collection-group
   index on `screens`.
3. Device reloads asset data

Not yet covered: an asset referenced only through a shared screen
(`pairs/{pairId}/sharedScreens`), which needs a pair → device traversal.

---

## 8.4 Brightness and Sleep Mode

Implemented as the persistent path only:

1. App writes `brightness` / `sleepMode` to `devices/{deviceId}`, in the same
   `update()` that increments `configVersion`, so the bump is atomic with the data
2. App rings the RTDB doorbell
3. Device picks the change up on its 60 s device-doc poll and applies it outside the
   `configVersion` guard

The "instant" variant (app writes an RTDB command, device applies immediately) is **not
implemented**. It would need the device to read RTDB, and that read is currently disabled —
`ENABLE_RTDB_DOORBELL 0`, because Firestore and RTDB share one blocking TLS client and the
repeated read wedged the device. So 60 s is the real worst-case latency.

Brightness has a second writer, the device's physical +/- buttons. The device applies the
cloud value only when the document value *changes*, so a button press is not reverted by the
next poll. See `docs/firebase_documentation.md` §3.4 for the field shapes.

---

# 9. Backend Abstraction in Flutter

In Flutter, backend is abstracted via:

```
FirebaseRepository
BleRepository
```

Features depend only on interfaces.

Example:

```
abstract class DeviceRepository {
  Stream<DeviceModel> watchDevice(String deviceId);
  Future<void> updateDeviceSettings(...);
}
```

Concrete implementation:

```
FirebaseDeviceRepository
```

This ensures:

* Testability
* Replaceable backend
* Clean architecture

---

# 10. Security Rules Strategy

Firestore rules enforce:

* Users can only read their devices
* SharedScreens readable only if pairId matches
* Assets readable by owner or public default
* Device writes limited to allowed fields

RTDB rules:

* Device writes to its own presence/telemetry
* App writes commands only to owned devices

---

# 11. Time Synchronization Model

Mobile app does not provide time.

Device syncs time via:

* NTP
* Or server timestamp (optional)

Mobile app only configures clock style and colors.

---

# 12. Offline Strategy

If app offline:

* Cached Firestore data used
* Edits queued by Firebase SDK
* Device continues using last config

If device offline:

* App shows offline indicator
* Config updates remain pending

---

# 13. Backend Design Principles

* Cloud as source of truth
* Device autonomous after sync
* Shared content referenced, not duplicated
* RTDB only for live state
* Firestore for configuration
* BLE only for onboarding

---

# 14. Summary

The TwinGlow mobile backend architecture is:

* Firebase-native
* Event-driven via configVersion (~60 s; an RTDB doorbell to cut this to ~5 s is
  written by the app but not yet consumed by the device)
* Reference-based for shared content
* Cleanly separated from UI
* Compatible with ESP32 FirebaseClient design
* Prepared for future scaling
