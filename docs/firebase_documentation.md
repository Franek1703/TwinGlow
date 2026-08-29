# Firebase Documentation

This document defines **what is stored in Firestore vs Realtime Database**, and the recommended **data formats** for screens, pairing, shared content, and pixel assets (images + animations) for a 16×16 matrix.

---

## 1. Firebase Services and Responsibilities

### 1.1 Firestore (Configuration + Content)

Firestore is used as the **source of truth** for:

- Users and device access
- Pair relationships
- Device-local screen playlists (layout & order)
- **Shared screen content between paired users** (`sharedScreens`)
- Pixel assets (static images + animations)

Firestore is ideal because the data is structured, queryable, and versionable.

### 1.2 Realtime Database (Presence + Telemetry + Commands)

Use RTDB for:

- Device presence / heartbeat
- Optional live telemetry (BME680 data)
- Optional command queue (e.g., “reload config”, “force screen now”)

In this architecture, **the device chooses the active screen locally**, so RTDB is *not* the source of truth for the active screen.

---

## 2. Identity Model

### 2.1 User owns devices via membership (no ownerUid inside `/devices`)

You prefer: “devices assigned to users”, not “owner inside device doc”.

We implement this with a membership subcollection:

- `/users/{uid}/devices/{deviceId}` → access/membership document
- `/devices/{deviceId}` → device metadata only

This is flexible and avoids hard-coding ownership in the device document.

---

## 3. Firestore Data Model

### 3.1 Collections Overview

```
/users/{uid}
/users/{uid}/devices/{deviceId}

/devices/{deviceId}
/devices/{deviceId}/screens/{screenId}

/pairs/{pairId}
/pairs/{pairId}/sharedScreens/{sharedScreenId}

/assets/{assetId}

```

---

### 3.2 `/users/{uid}`

**Purpose:** user profile and high-level settings.

```json
{
  "displayName": "Szymon",
  "photoURL": null,
  "createdAt": "serverTimestamp",
  "timezone": "Europe/Warsaw",
  "activePairId": "pair_abc"
}

```

---

### 3.3 `/users/{uid}/devices/{deviceId}`

**Purpose:** user-device access mapping (ownership, shared access, device nickname).

```json
{
  "role": "OWNER",
  "nameOverride": "Bedroom TwinGlow",
  "addedAt": "serverTimestamp"
}

```

Recommended roles:

- `OWNER`
- `ADMIN` (optional)
- `VIEWER` (optional)

---

### 3.4 `/devices/{deviceId}`

**Purpose:** device metadata and firmware/config management.

```json
{
  "name": "TwinGlow 1",
  "createdAt": "serverTimestamp",
  "fwVersion": "1.0.0",
  "hw": {
    "matrix": "16x16",
    "bme680": true
  },
  "configVersion": 42,
  "timezone": "Europe/Warsaw",
  "tzPosix": "CET-1CEST,M3.5.0,M10.5.0/3"
}

```

Why both timezone fields?

The device carries no tzdata, so it cannot turn `Europe/Warsaw` into an offset.
The app resolves the IANA name to a POSIX TZ rule and writes both:

- `timezone` — the IANA name. Display only; the firmware never reads it. It
  exists so the zone is legible in the app and in the Firestore console.
- `tzPosix` — what the firmware actually applies, via `setenv("TZ", ...)` and
  `configTzTime()`. The rule carries its own DST transitions, so the device
  handles the March/October changeovers itself even if it never hears from the
  app again.

The app fills these in from the phone's timezone the first time it sees a device
without one, and only then — a set zone is changed by the picker in Device
Settings, never silently by a phone that has travelled. The firmware caches
`tzPosix` in NVS, so the clock is correct at boot and while offline. When the
field is absent the device falls back to `DEFAULT_TZ_POSIX` (`UTC0`).

The app's table is generated from the system tzdata by
`tools/gen_posix_timezones.js`; see `twin_glow/lib/core/utils/posix_timezones.dart`.

Why `configVersion`?

- ESP32 can periodically check only this field.
- If it changes, device reloads screens + sharedScreens + assets.

---

## 3.5 `/devices/{deviceId}/screens/{screenId}` (Device-local playlist)

### Purpose

Defines the **device-local screen playlist**, including:

- screen order and duration (per device)
- screen type
- whether the screen is enabled (per device)
- optional link to **shared screen content** stored under the pair

Each screen document is **local to the device**, so each user can:

- keep the same shared content
- but arrange screen order independently

---

### Common fields (all screen types)

```json
{
  "order": 10,
  "enabled": true,
  "type": "CLOCK",
  "durationMs": 8000
}

```

Field description:

| Field | Type | Description |
| --- | --- | --- |
| `order` | number | Order in the screen playlist (device-specific) |
| `enabled` | boolean | Whether the screen is active on this device |
| `type` | string | Screen type |
| `durationMs` | number | How long the screen is displayed before rotation |

---

### Supported `type` values

- `CLOCK`
- `IMAGE`
- `ANIMATION`
- `SENSOR`
- `GAME` *(future)*

---

### Shared screen linkage (`sharedRef`)

A screen becomes **shared** if it contains:

```json
"sharedRef": {
  "pairId": "pair_abc",
  "sharedScreenId": "shared_image_01"
}

```

- If `sharedRef` is present → the screen’s content is loaded from `/pairs/{pairId}/sharedScreens/{sharedScreenId}`
- If `sharedRef` is absent → the screen is fully local and does not share content

Only these types should use `sharedRef`:

- `IMAGE`
- `ANIMATION`

---

### Manual asset switching (from device)

Manual switching is configured inside the **shared screen content** (not inside the device-local screen), so both users see the same shared pool:

- the device rotates screens locally
- but when displaying a shared screen, it can cycle through the shared asset pool
- the currently selected asset is **runtime state** (device-side) and is **not stored in Firestore**

---

## 3.5.1 CLOCK Screen (local, generated on device)

```json
{
"order":10,
"enabled":true,
"type":"CLOCK",
"durationMs":10000,

"config":{
"format":"24H",
"showSeconds":false,
"blinkColon":true,

"layout":"HHMM_PLUS_SECONDS_BAR",

"fgColor":16777215,
"accentColor":65535,
"bgColor":0,
"brightness":80
}
}

```

### Field description (CLOCK `config`)

| Field | Type | Description |
| --- | --- | --- |
| `format` | string | `"24H"` or `"12H"` |
| `showSeconds` | boolean | Whether seconds are shown as digits (usually false on 16×16) |
| `blinkColon` | boolean | Whether the colon blinks every second |
| `layout` | string | Clock layout variant (see below) |
| `fgColor` | int | Main digit color (`0xRRGGBB`) |
| `accentColor` | int | Colon / seconds bar / accents color |
| `bgColor` | int | Background color (usually `0`) |
| `brightness` | number | Screen brightness (0–255) |

### Recommended `layout` values (CLOCK)

- `BIG_HHMM` – large HH:MM digits
- `HHMM_PLUS_SECONDS_BAR` – HH:MM + seconds progress bar (recommended)
- `MINIMAL` – small digits, more empty space

### Notes

- CLOCK screen is **not shareable**
- Fully generated locally on the ESP32
- Time is obtained via **NTP**, not Firebase
- The **timezone** does come from Firebase: `tzPosix` on `/devices/{deviceId}`
  (see 3.4). NTP supplies the epoch, `tzPosix` turns it into local time.
- Firebase stores **configuration only**, never pixel data

---

### 3.5.2 IMAGE screen (device-local layout + shared content)

```json
{
  "order": 20,
  "enabled": true,
  "type": "IMAGE",
  "durationMs": 8000,
  "sharedRef": {
    "pairId": "pair_abc",
    "sharedScreenId": "shared_image_01"
  }
}

```

---

### 3.5.3 ANIMATION screen (device-local layout + shared content)

```json
{
  "order": 30,
  "enabled": true,
  "type": "ANIMATION",
  "durationMs": 12000,
  "sharedRef": {
    "pairId": "pair_abc",
    "sharedScreenId": "shared_anim_01"
  }
}

```

---

## 3.5.4 SENSOR Screen (local, generated on device)

```json
{
"order":40,
"enabled":true,
"type":"SENSOR",
"durationMs":8000,

"config":{
"mode":"AUTO_CYCLE",
"cycleMs":2500,
"show":["temperature","humidity"],
"units":"METRIC",

"layout":"BIG_VALUE_WITH_LABEL",

"fgColor":16753920,
"accentColor":16777215,
"bgColor":0,
"brightness":70
}
}

```

### Field description (SENSOR `config`)

| Field | Type | Description |
| --- | --- | --- |
| `mode` | string | `"AUTO_CYCLE"` or `"SINGLE"` |
| `cycleMs` | number | Time between metric switches (AUTO_CYCLE) |
| `show` | array | Metrics to display (`temperature`, `humidity`, `pressure`) |
| `units` | string | `"METRIC"` or `"IMPERIAL"` |
| `layout` | string | Sensor layout variant |
| `fgColor` | int | Main value color (`0xRRGGBB`) |
| `accentColor` | int | Label / icon / bar color |
| `bgColor` | int | Background color |
| `brightness` | number | Screen brightness (0–255) |

### Recommended `layout` values (SENSOR)

- `BIG_VALUE_WITH_LABEL` – large number + small label (recommended)
- `VALUE_WITH_BAR` – number + vertical bar (e.g. humidity)
- `ICON_AND_VALUE` – icon + value (if space allows)

### Notes

- SENSOR screen is **not shareable**
- Data is read **locally** from the BME680
- Firebase stores **only presentation config**, never sensor values
- Live sensor values may optionally be mirrored to RTDB for the app

---

## 3.6 `/pairs/{pairId}`

**Purpose:** defines a connection between two users.

```json
{
  "userA": "uid_1",
  "userB": "uid_2",
  "createdAt": "serverTimestamp",
  "state": "ACTIVE"
}

```

Recommended `state` values:

- `INVITED`
- `ACTIVE`
- `BLOCKED`
- `ENDED`

---

## 3.7 `/pairs/{pairId}/sharedScreens/{sharedScreenId}` (Shared screen content)

### Purpose

Defines **shared content** for a screen, editable by both users in the pair.

This is where shared configuration lives:

- default asset
- pool of available assets
- manual switching settings
- animation loop settings

This document is referenced by one or more device-local screens via `sharedRef`.

---

### Shared IMAGE screen example

```json
{
  "type": "IMAGE",

  "defaultAssetId": "asset_heart_01",
  "availableAssetIds": [
    "asset_heart_01",
    "asset_smile_02",
    "asset_sad_01"
  ],

  "allowManualSwitch": true,

  "lastEditedBy": "uid_2",
  "lastEditedAt": "serverTimestamp"
}

```

---

### Shared ANIMATION screen example

```json
{
  "type": "ANIMATION",

  "defaultAssetId": "asset_anim_blink",
  "availableAssetIds": [
    "asset_anim_blink",
    "asset_anim_wave",
    "asset_anim_heart"
  ],

  "loop": true,
  "allowManualSwitch": true,

  "lastEditedBy": "uid_1",
  "lastEditedAt": "serverTimestamp"
}

```

---

## 4. Assets in Firestore (Images + Animations)

Assets are stored in Firestore because 16×16 content is small.

### 4.1 Color format

Store colors as **RGB888**, because:

- it’s standard for mobile preview rendering
- it’s human-debuggable
- conversion to device-native formats (e.g., RGB565) is trivial on ESP32

### 4.2 Color encoding recommendation

**Option A (recommended):** integer `0xRRGGBB`

- compact and fast
- example: `16711680` (0xFF0000)

**Option B:** hex string `"#RRGGBB"`

- more human-friendly, slightly larger

---

### 4.3 Asset document structure

**Collection:** `/assets/{assetId}`

```json
{
  "ownerUid": "uid_1",
  "type": "IMAGE",
  "width": 16,
  "height": 16,
  "encoding": "SPARSE_I16_RGB888",
  "createdAt": "serverTimestamp",
  "tags": ["heart"]
}

```

---

### 4.4 Static image asset: sparse pixels

**Sparse encoding** stores only pixels that are not black.

- `index` = 0..255, computed as `index = y*16 + x`
- `color` = RGB888 integer `0xRRGGBB`

**Format:** Array of objects (Firestore-friendly format)

```json
{
  "ownerUid": "uid_1",
  "type": "IMAGE",
  "width": 16,
  "height": 16,
  "encoding": "SPARSE_I16_RGB888",
  "pixels": [
    {"index": 34, "color": 16711680},
    {"index": 35, "color": 16711680},
    {"index": 50, "color": 16711680}
  ],
  "createdAt": "serverTimestamp",
  "tags": ["heart", "default"]
}
```

**Field descriptions:**
- `index`: Pixel position (0-255), calculated as `y * 16 + x`
- `color`: RGB888 color value (24-bit, `0xRRGGBB` format)

Black pixels are implicit (not stored).

Black pixels are implicit (not stored).

---

### 4.5 Animation asset: delta sparse frames

Store an initial frame and only changes per frame:

- `basePixels` = initial sparse frame (array of objects)
- `frames[]` = list of deltas (each frame contains array of objects)
- delta pixels can include black to turn pixels off (`color = 0x000000`)

**Format:** Array of objects for both `basePixels` and frame `pixels`

```json
{
  "ownerUid": "uid_1",
  "type": "ANIMATION",
  "width": 16,
  "height": 16,
  "encoding": "DELTA_SPARSE_I16_RGB888",

  "basePixels": [
    {"index": 120, "color": 16776960},
    {"index": 121, "color": 16776960}
  ],

  "frames": [
    { 
      "delayMs": 80, 
      "pixels": [
        {"index": 120, "color": 0},
        {"index": 121, "color": 16776960}
      ]
    },
    { 
      "delayMs": 80, 
      "pixels": [
        {"index": 120, "color": 16776960},
        {"index": 121, "color": 0}
      ]
    }
  ],

  "loop": true,
  "createdAt": "serverTimestamp",
  "tags": ["blink"]
}
```

**Field descriptions:**
- `basePixels`: Array of `{"index": i, "color": c}` objects for the initial frame
- `frames`: Array of frame objects, each containing:
  - `delayMs`: Delay before next frame (milliseconds)
  - `pixels`: Array of `{"index": i, "color": c}` objects (delta changes)

---

### 4.6 Optional: full frames

If you later need dense frames:

- `encoding: "FULL_RGB888"`
- `frame`: array of 256 colors

---

## 5. Realtime Database Model

RTDB is for live state only.

### 5.1 Paths Overview

```
/presence/{deviceId}
/telemetry/{deviceId}
/config/{deviceId}/configVersion
/commands/{deviceId}/{commandId}

```

---

### 5.2 `/presence/{deviceId}`

```json
{
  "online": true,
  "lastSeenMs": 1700000000000
}

```

**Field Descriptions:**
- `online`: Boolean indicating device connectivity status
- `lastSeenMs`: Epoch timestamp in milliseconds (Unix time * 1000)

**Update Frequency:**
- ESP32 updates presence every **20 seconds** (`PRESENCE_UPDATE_INTERVAL_MS = 20000`)
- Updates occur only when Wi-Fi is connected
- Timestamp uses `time(nullptr) * 1000` if NTP sync succeeded, otherwise falls back to `millis()`

**Implementation Note:**
Fields are set individually (not as a JSON object) to avoid JSON parsing issues with Firebase RTDB:
- `/presence/{deviceId}/online` = boolean
- `/presence/{deviceId}/lastSeenMs` = number (long long)

---

### 5.3 `/telemetry/{deviceId}` (optional)

```json
{
  "temperatureC": 21.3,
  "humidityPct": 43.2,
  "pressureHPa": 1008.6,
  "gasOhms": 12000,
  "updatedMs": 1700000000000
}

```

---

### 5.4 `/config/{deviceId}/configVersion` (config-change doorbell)

```json
{
  "configVersion": 17
}

```

A bare monotonic counter, written by the app and read by the device. It is a
**notification, not data** - the number carries no meaning of its own and is
deliberately *not* required to match the Firestore `configVersion`.

**Why it exists:** screens live in Firestore, and Firestore has no listen support
over the REST API the firmware uses, so the device can only poll. Polling the
device document often enough to feel instant is expensive; polling one RTDB
integer is not. The app ticks this node on every config change, the device reads
it every `REVISION_POLL_INTERVAL_MS` (5 s), and any change makes it run the
Firestore check immediately instead of waiting out the 60 s poll.

**Writer:** `_ringConfigDoorbell()` in
`twin_glow/lib/services/firebase/firebase_repository_impl.dart`, called from
`_incrementDeviceConfigVersion()` (screen add/update/delete/reorder, asset
add/update/delete) and from `updateDevice()`.

**Reader:** `RtdbRepo::getConfigRevision()` →
`checkConfigRevision()` in `TwinGlow.ino`, which delegates the real comparison to
`checkConfigVersion()`.

**Failure behaviour:** the write is best-effort and its failure never fails the
edit; the read failing leaves the device's remembered value untouched. In both
cases the 60 s Firestore poll still delivers the change, just slower.

**Security rules.** The device bypasses rules (legacy database secret), but the
app writes this node as the signed-in user, so the rules must permit it. Rules
for this project are maintained in the Firebase console and are not in this repo
- **merge** the following into the existing ruleset rather than replacing it:

```json
"config": {
  "$deviceId": {
    ".read": "auth != null",
    ".write": "auth != null && root.child('users').child(auth.uid)
                 .child('devices').child($deviceId).exists()",
    "configVersion": { ".validate": "newData.isNumber()" }
  }
}
```

---

### 5.5 `/commands/{deviceId}/{commandId}` (optional, not implemented)


```json
{
  "type": "RELOAD_CONFIG",
  "payload": {},
  "createdMs": 1700000000000,
  "fromUid": "uid_1",
  "status": "PENDING"
}

```

Possible command types:

- `RELOAD_CONFIG`
- `FORCE_SCREEN` (optional feature)
- `SET_BRIGHTNESS` (optional feature)

Device processing:

- listens for new commands
- executes
- updates status to `ACK` or `ERROR`

---

## 6. ESP32 Data Loading Strategy (Cloud-driven screens)

### 6.1 Boot / reload flow

1. Read `/devices/{deviceId}.configVersion`
2. Fetch `/devices/{deviceId}/screens` ordered by `order`
3. For screens with `sharedRef`, fetch `/pairs/{pairId}/sharedScreens/{sharedScreenId}`
4. Collect all referenced `assetId`s from sharedScreens (and local screens if used later)
5. Fetch required `/assets/{assetId}` documents
6. Build local cache (RAM; optional flash later)

### 6.2 Runtime behavior

- Device runs playlist locally (screen scheduler)
- Clock and sensor screens render locally
- Image/animation screens render using shared content + cached assets

### 6.3 Detecting configuration updates

Two paths, both ending in the same reload:

1. **Doorbell (fast, ~5 s).** The app ticks
   `/config/{deviceId}/configVersion` in RTDB on every change. The device reads
   that one integer every 5 s; if it moved, it runs the Firestore check straight
   away. See §5.4.
2. **Poll (fallback, ~60 s).** Independently, the device re-reads
   `/devices/{deviceId}` every 60 s.

Either way the decision is the same: compare Firestore's `configVersion` against
the last one successfully loaded, and rerun the reload flow when they differ. The
doorbell only changes *when* that comparison happens, so a missed or failed RTDB
read costs latency, never correctness.

Note the reload is marked consumed only after the screens actually load, so a
failed fetch leaves the old version in place and the next poll retries.