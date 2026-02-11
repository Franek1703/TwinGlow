# Mobile App – Architecture & Screen Documentation


This document describes the **mobile application architecture, screen structure, user flows, and UI behavior** for the TwinGlow project.

The mobile app is the **primary control plane** for TwinGlow devices, responsible for:

- onboarding users,
- provisioning devices,
- managing screens and assets,
- configuring sharing and pairing,
- and controlling device behavior via Firebase.

---

## 1. App Overview

**Platform:** iOS / Android

**Backend:** Firebase (Auth, Firestore, Realtime Database)

**Connectivity:** Bluetooth Low Energy (BLE), Wi-Fi (indirect via device)

The app follows a **cloud-driven model**, where:

- devices execute logic locally,
- the app edits configuration stored in Firebase,
- devices react to configuration changes and RTDB commands.

---

## 2. High-Level Navigation Structure

### App Entry Flow

```
Launch
 ├─ Onboarding (first launch only)
 ├─ Authentication
 └─ Device Setup (if no devices)
      └─ Main Application
```

### Main App Tabs (Bottom Navigation)

1. **Home** – device + screen playlist
2. **Assets** – asset library & editor
3. **Settings** – device, pairing, account

---

## 3. Onboarding Flow

### Purpose

- Explain the product
- Set expectations
- Introduce pairing and sharing concepts

### Structure (2–3 screens)

### Screen 1 – What is TwinGlow

- TwinGlow connects two devices emotionally
- Images, animations, and live data
- Works offline after sync

### Screen 2 – Screens & Sharing

- Devices run screen playlists
- Some screens can be shared with a paired user
- Sharing is always explicit and controlled

### Screen 3 – Add Your Device

- Device connects via Bluetooth
- App sends Wi-Fi credentials and user ID
- CTA: **Get Started**

Notes:

- Skip button available
- Onboarding is shown once (stored locally)

---

## 4. Authentication

### Supported Method

- Email / Password (Firebase Authentication)

### Flow

- Login
- Create account
- Password recovery

### Post-login routing

- If user has **no devices** → Add Device
- If user has **at least one device** → Home

---

## 5. Device Provisioning (BLE)

### Purpose

Provision ESP32 device with:

- Wi-Fi credentials
- Firebase user ID

### Flow

1. Permissions
    - Bluetooth
    - (Optional) Location (OS requirement for BLE scan)
2. Device Scan
    - List nearby TwinGlow devices
    - Show signal strength (RSSI)
3. Provisioning
    - Select Wi-Fi network
    - Enter password
    - Send credentials + `uid` over BLE
4. Registration
    - Device connects to Wi-Fi
    - Registers itself in Firestore
    - Appears in `/users/{uid}/devices`
5. Success
    - App navigates to Home
    - Device is now controllable

Failure handling:

- Timeout
- Wrong Wi-Fi password
- Device reset instructions

---

## 6. Home Screen (Main Screen)

The Home screen represents **one active device** and its **screen playlist**.

---

### 6.1 Device Header

Located at the top of the screen.

Displays:

- Device name (editable)
- Online / offline status (RTDB presence)
- Hardware indicators (e.g. BME680 available)
- Connection state

Tap action:

- Opens **Device Details**

---

### 6.2 Screen Playlist (Vertical List)

Screens are displayed as a **vertical list**.

Each list item represents one screen from:

```
/devices/{deviceId}/screens/{screenId}
```

---

### Screen Tile Layout

Each screen tile contains:

- **Screen type icon**
    - CLOCK
    - IMAGE
    - ANIMATION
    - SENSOR
    - GAME (future)
- **Preview**
    - 16×16 rendered preview (for image/animation)
    - Icon-based preview for generated screens
- **Metadata**
    - Screen name or type
    - Duration
    - Enabled/disabled state
- **Sharing Indicator (top-right corner)**
    - Visible only for IMAGE / ANIMATION / GAME
    - Small icon (e.g. link/heart symbol)
    - Indicates that the screen is shared
    - Does **not** show who it’s shared with here

---

### Interactions

- **Tap screen tile**
    
    → Open Screen Editor
    
- **Long press / Edit mode**
    
    → Reorder screens via drag & drop
    
- **Toggle enabled**
    
    → Enables/disables screen in device playlist
    

---

## 7. Screen Editor

Each screen has its own editor based on `type`.

### Common Fields

- Enabled
- Duration
- (Optional) Display name
- Sharing status (if applicable)

---

### 7.1 CLOCK Screen Editor

- Digital style options
- Show / hide seconds
- Color configuration:
    - Digit color
    - Colon color
    - Background color

Notes:

- Not shareable
- Fully generated locally on device

---

### 7.2 SENSOR Screen Editor (BME680)

- Select displayed values:
    - Temperature
    - Humidity
    - Pressure
- Units (metric/imperial)
- Color configuration:
    - Numbers
    - Accent
    - Background

Notes:

- Not shareable
- Disabled automatically if sensor not present

---

### 7.3 IMAGE Screen Editor

- Sharing toggle
- Default image selection
- List of available images for manual switching
- Fallback image
- Preview

If shared:

- Shows pairing info
- Explains that both users can modify content

---

### 7.4 ANIMATION Screen Editor

- Same as IMAGE
- Loop control
- Frame timing info

---

## 8. Assets Tab

### Structure

Two tabs:

1. **My Assets**
2. **Default Assets**

---

### Asset List

Each asset shows:

- 16×16 preview
- Name
- Type (IMAGE / ANIMATION)
- Tags

Filters:

- Type
- Tags
- Search

Actions:

- Edit
- Delete (own assets only)
- Assign to screen

---

## 9. Asset Editor

### 9.1 Image Editor

- 16×16 pixel grid
- RGB color picker
- Tools:
    - Pencil
    - Eraser
    - Fill
    - Mirror X / Y
    - Clear

Metadata:

- Name
- Tags

Save:

- Stored in Firestore `/assets/{assetId}`

---

### 9.2 Animation Editor

- Frame timeline
- Per-frame delay
- Frame duplication
- Preview playback

Storage:

- Sparse pixel format (delta frames)
- Optimized for ESP32 memory

---

## 10. Settings Tab

### Sections

### Account

- User profile
- Sign out

### Devices

- Device list
- Rename device
- Remove device

### Pairing

- Pair status
- Invite user
- Accept invite
- Unpair

### Device Settings

- Global brightness
- Sleep mode:
    - Enabled
    - Start time
    - End time
    - Weekdays selection

---

## 11. Design Principles

- Vertical lists for clarity and scalability
- Explicit sharing indicators
- No hidden or automatic sharing
- Device-first logic, app as configuration UI
- Offline-friendly by design

---

## 12. Summary

The TwinGlow mobile app is designed to be:

- Intuitive
- Predictable
- Cloud-driven
- Extensible

The vertical screen playlist, clear sharing indicators, and strong separation between **screens**, **assets**, and **pairing** ensure long-term maintainability and a clean user experience.