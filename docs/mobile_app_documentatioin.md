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

- Same as IMAGE; `/screen/animation/:id` already passes `ScreenType.animation`, so the editor
  filters the asset pool to animations
- Frame timing info
- **No loop control** — every animation loops, by design

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

`AssetEditorAnimationView` + `AnimationEditorCubit`, separate from the image editor.

- Horizontally reorderable frame timeline: select, add blank, duplicate, delete
- Per-frame duration, stepped in 50 ms, with inline validation
- Duplication deep-copies, so editing a copy never writes through to its source
- The pixel grid reloads when the selected frame changes
- Always-looping preview with play/pause and restart; frames stay editable while paused
- The same pencil, eraser, fill, clear, mirror, colour, name and tag controls as the image editor

A new animation opens on **two blank 200 ms frames**.

**Limits** (`AnimationCodec`, enforced before the write and again on the device):

| Limit | Value |
|---|---|
| Frames | 2–16 |
| Duration per frame | 50–5000 ms |
| Packed characters, base + all deltas | 8192 |
| Visible pixels | at least one |

An animation that breaks a limit is **rejected, not truncated**: the save fails with an inline
message and the frames stay in the editor for the retry.

Storage:

- One `/assets/{assetId}` document, `DELTA_SPARSE_PACKED_V1` (see the Firebase doc §4.5)
- First frame packed in full, every later frame packed as the change from the one before it
- Optimized for ESP32 memory

**Routing.** `/asset/create/animation` opens the animation editor. `/asset/edit/:id` dispatches on
a `?type=` query parameter that the library builds from the asset it already holds
(`assetEditorFor` in `app_router.dart`); without it, the link keeps the previous image behaviour.
Editing previously opened the image editor for *every* asset, which flattened an animation to its
first frame on the next save.

**Previews.** Library and selector thumbnails show the first frame with a play badge; the editor
and the active screen preview play the whole sequence.

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

These are **per device** and live on the Device Configuration screen (reached from a device,
next to Time zone) — not in the global Settings tab, since a user with two devices sets each
one independently.

- Brightness (slider, floored at 5% so the panel cannot be lost — only sleep mode may blank it)
- Sleep mode:
    - Enabled
    - Start time
    - End time
    - Brightness while asleep (0 = display off)

Weekday selection is **not implemented**: the window applies every night. Adding it means a
day bitmask in the `sleepMode` map plus one more check on the device.

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