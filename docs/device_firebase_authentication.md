# Firebase Authentication & Communication (ESP32)


---

This document describes **how the TwinGlow ESP32 device authenticates and communicates with Firebase**, including **Authentication**, **Realtime Database**, and **Firestore**, based on the official `FirebaseClient` library.

The goal is to keep the device-side authentication **simple, reliable, and suitable for embedded constraints**, while maintaining a clean upgrade path for production security.

---

## 1. Overview

The TwinGlow ESP32 communicates with Firebase to:

- Read and write **device configuration** (Firestore)
- Read and write **runtime state and telemetry** (Realtime Database)
- Register and claim devices to users
- Synchronize shared content between paired users

The device **does not use Firebase Admin SDK** and **does not run a backend server**.

---

## 2. Firebase Services Used

TwinGlow uses the following Firebase services:

- **Firebase Authentication**
- **Firebase Realtime Database (RTDB)**
- **Firebase Firestore**

The ESP32 communicates directly with Firebase via HTTPS using the `FirebaseClient` library.

---

## 3. Authentication Strategy (ESP32)

### 3.1 Chosen Authentication Method

For the ESP32 device, TwinGlow uses:

> **Legacy Realtime Database Secret (Database Secret)**
> 
> 
> *(as supported by FirebaseClient)*
> 

This method is chosen because:

- It works reliably on embedded devices
- It does **not** require token refresh logic
- It avoids OAuth2 complexity on ESP32
- It is explicitly supported by `FirebaseClient`

⚠️ **Important:**

Database secrets are **deprecated by Firebase**, but **still supported** and acceptable for:

- prototypes
- academic projects
- controlled environments
- devices without user credentials

---

### 3.2 Why NOT User Authentication on ESP32

The ESP32 **does not authenticate as a user**.

Reasons:

- Users authenticate via the **mobile app**
- ESP32 only needs device-level access
- User identity (`uid`) is passed to the device **once via BLE provisioning**
- All user-specific logic lives in Firestore rules and data structure

---

## 4. Firebase Console Setup (Required)

### 4.1 Enable Authentication

Even if the ESP32 does not authenticate as a user, **Authentication must be enabled** in the project.

Steps:

1. Open **Firebase Console**
2. Go to **Authentication**
3. Click **Get started**
4. Enable at least one provider:
    - Email/Password **or**
    - Anonymous

This is required because some Firebase APIs will return **HTTP 400** if Authentication is not initialized.

---

### 4.2 Obtain Web API Key

The **Web API Key** is required by `FirebaseClient`.

Steps:

1. Go to **Project Settings**
2. Open the **General** tab
3. Copy **Web API Key**

This key is used in:

- `CustomAuth`
- `UserAuth`
- `IDToken` flows
- and also required internally by the client

---

### 4.3 Enable Realtime Database

Steps:

1. Go to **Realtime Database**
2. Click **Create Database**
3. Choose a region
4. Start in **test mode** (for development)

You will see a warning about insecure rules — this is expected at this stage.

---

### 4.4 Obtain Realtime Database URL

From the **Data** tab in Realtime Database, copy:

```
https://<project-id>.<region>.firebasedatabase.app
```

This value is used as:

```cpp
DATABASE_URL
```

---

### 4.5 Obtain Database Secret (Legacy)

Steps:

1. Go to **Project Settings**
2. Open **Service Accounts**
3. Select **Database secrets**
4. Copy the secret for your database

⚠️ Firebase marks this as **deprecated**, but it is still functional and supported by `FirebaseClient`.

---

## 5. Authentication Flow on ESP32

### 5.1 Authentication Components Used

On the ESP32, the following components are used:

- `ServiceAuth` (legacy database secret)
- Web API Key
- Database URL

No user login, no token refresh, no OAuth2.

---

### 5.2 Authentication Flow Summary

1. ESP32 boots
2. Loads Wi-Fi credentials from NVS
3. Connects to Wi-Fi
4. Initializes Firebase client
5. Authenticates using **database secret**
6. Firebase session remains valid indefinitely
7. Device can read/write RTDB and Firestore

There is **no login / logout lifecycle**.

---

## 6. Realtime Database Usage (ESP32)

### 6.1 Purpose of RTDB

Realtime Database is used for **live, ephemeral data**:

- Device presence / heartbeat
- Optional sensor telemetry (BME680)
- Runtime commands

RTDB is **not** used for persistent configuration.

---

### 6.2 RTDB Paths Used

```
/presence/{deviceId}
/telemetry/{deviceId}
/commands/{deviceId}/{commandId}
```

---

### 6.3 Typical ESP32 RTDB Operations

- Periodically update `/presence/{deviceId}`
- Optionally push sensor readings to `/telemetry/{deviceId}`
- Listen for new entries under `/commands/{deviceId}`

RTDB communication is lightweight and tolerant to reconnections.

---

## 7. Firestore Usage (ESP32)

### 7.1 Purpose of Firestore

Firestore is used as the **source of truth** for:

- Device metadata
- Screen configuration
- Assets (images, animations)
- Pairing and sharing relationships

Firestore data changes **infrequently**, but must be strongly consistent.

---

### 7.2 Firestore Operations Used by ESP32

The ESP32 performs:

- `GET` document (device config, assets)
- `LIST` collections (screens)
- `UPDATE` small fields (capability flags, configVersion)

It does **not**:

- run queries with complex filters
- listen to realtime snapshots
- perform batch writes

---

### 7.3 Config Versioning Pattern

The ESP32 periodically checks:

```
/devices/{deviceId}.configVersion
```

If the value changes:

- reload all screens
- reload referenced assets
- rebuild local cache

This avoids Firestore listeners on embedded hardware.

---

## 8. Security Rules (Development vs Production)

### 8.1 Development Phase

During development:

- RTDB rules may allow broad access
- Firestore rules may be permissive

This is acceptable for:

- local testing
- academic projects
- closed environments

---

### 8.2 Production Direction (Future)

For production, recommended upgrades:

- Replace database secret with **Service Account OAuth2**
- Move privileged operations to a backend
- Restrict ESP32 access to device-scoped paths only
- Enforce user ownership in Firestore rules

The current architecture **does not block this migration**.

---

## 9. Summary

TwinGlow’s Firebase communication model:

- Uses **FirebaseClient** officially supported flows
- Keeps ESP32 authentication simple and stable
- Separates **user identity (mobile app)** from **device identity**
- Uses RTDB for live data and Firestore for configuration
- Is suitable for embedded constraints and future-proofed

This setup is considered **correct, intentional, and appropriate** for the TwinGlow project at its current stage.