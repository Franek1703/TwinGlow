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
/users/{uid}                                    exists
/users/{uid}/devices/{deviceId}                 exists

/devices/{deviceId}                             exists
/devices/{deviceId}/screens/{screenId}          exists

/pairs/{pairId}                                 EMPTY - never created, see §7
/pairs/{pairId}/sharedScreens/{sharedScreenId}  EMPTY - never created, see §7

/assets/{assetId}                               exists

/test/{docId}                                   leftover test data, unused

```

---

### 3.2 `/users/{uid}`

**Purpose:** user profile and high-level settings.

What the app actually writes today:

```json
{
  "email": "user@example.com",
  "createdAt": "serverTimestamp"
}

```

| Field | Status |
| --- | --- |
| `email` | Written on sign-up. Used to look up a user when sending a pairing invite |
| `createdAt` | Written on sign-up |
| `displayName` | Read by the app, but never written — always null in practice |
| `photoURL`, `timezone`, `activePairId` | Planned, not implemented. Nothing reads or writes them |

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

What is actually written today — `fwVersion`, `hw` and `configVersion` by the device,
`timezone` and `tzPosix` by the app:

```json
{
  "fwVersion": "1.0.0",
  "hw": {
    "bme680": false
  },
  "configVersion": 42,
  "timezone": "Europe/Warsaw",
  "tzPosix": "CET-1CEST,M3.5.0,M10.5.0/3"
}

```

`name`, `createdAt` and `hw.matrix` appear in earlier drafts of this document but are never
written by the device or the app. The app falls back to a placeholder when showing a device name.

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
  "type": "clock",
  "name": "Clock Screen",
  "durationMs": 8000
}

```

Field description:

| Field | Type | Description |
| --- | --- | --- |
| `order` | number | Order in the screen playlist (device-specific) |
| `enabled` | boolean | Whether the screen is active on this device |
| `type` | string | Screen type. The app writes it **lowercase**; the device uppercases it before comparing |
| `name` | string | Display name shown in the app |
| `durationMs` | number | How long the screen is displayed before rotation |

> **Not written today:** the app never writes `durationMs`. The device falls back to
> `SCREEN_DEFAULT_DURATION_MS`, so every screen currently uses the firmware default. The app also
> writes `previewData` (a 16×16 grid) which the device ignores.

---

### Supported `type` values

- `CLOCK`
- `IMAGE`
- `ANIMATION`
- `SENSOR`
- `GAME` *(future)*

---

### Asset pool (IMAGE / ANIMATION only)

A screen owns its own content. These fields are written **only** for `IMAGE` and `ANIMATION`
screens — `CLOCK` and `SENSOR` documents never carry them:

```json
{
  "isShared": false,
  "assetId": "asset_heart_01",
  "defaultAssetId": "asset_heart_01",
  "availableAssetIds": [
    "asset_heart_01",
    "asset_smile_02",
    "asset_sad_01"
  ],
  "allowManualSwitch": true
}

```

| Field | Type | Description |
| --- | --- | --- |
| `isShared` | boolean | Whether this screen is shared with the paired user |
| `assetId` | string | Legacy single-asset field, kept in sync with `defaultAssetId`. The device falls back to it when the pool is empty |
| `defaultAssetId` | string | Asset shown first. The device starts the pool here, not at index 0 |
| `availableAssetIds` | array&lt;string&gt; | The pool the action button cycles through, in cycle order |
| `allowManualSwitch` | boolean | When `false`, the action button will not cycle the pool |

Behavior notes:

- The device caches **every** asset in the pool on config load, so cycling is instant and works
  offline.
- Cycling needs at least two entries in the pool.
- The currently displayed asset is **runtime state on the device** and is deliberately never
  written back to Firestore — it resets to `defaultAssetId` on reboot or config reload, and the
  paired device does not follow it.

---

### Shared screen linkage

A shared screen carries two **flat string fields** (not a nested `sharedRef` map — the firmware
parses flat fields only):

```json
{
  "isShared": true,
  "pairId": "pair_abc",
  "sharedScreenId": "tg_f4ec6bb0ef83_screen_1770917521614"
}

```

- These point at the pointer document under the pair (see §3.7). They record *that* the screen is
  shared; the content stays on the screen document.
- `sharedScreenId` is deterministic — `{deviceId}_{screenId}` — so re-sharing overwrites rather
  than duplicating.
- When the screen has a pool of its own, the device uses it directly. It reads the pair's document
  only as a **fallback**, when `availableAssetIds` is empty and both `pairId` and `sharedScreenId`
  are set.
- Only `IMAGE` and `ANIMATION` screens are shareable.

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

### 3.5.2 IMAGE screen

A private screen with a three-image pool:

```json
{
  "order": 20,
  "enabled": true,
  "type": "image",
  "name": "Image Screen",
  "isShared": false,
  "assetId": "asset_heart_01",
  "defaultAssetId": "asset_heart_01",
  "availableAssetIds": [
    "asset_heart_01",
    "asset_smile_02",
    "asset_sad_01"
  ],
  "allowManualSwitch": true
}

```

The same screen once shared adds `"isShared": true`, `pairId` and `sharedScreenId`.

---

### 3.5.3 ANIMATION screen

Identical to IMAGE, with animation assets:

```json
{
  "order": 30,
  "enabled": true,
  "type": "animation",
  "name": "Animation Screen",
  "isShared": false,
  "assetId": "asset_anim_blink",
  "defaultAssetId": "asset_anim_blink",
  "availableAssetIds": [
    "asset_anim_blink",
    "asset_anim_wave"
  ],
  "allowManualSwitch": true
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

## 3.7 `/pairs/{pairId}/sharedScreens/{sharedScreenId}` (Shared screen pointer)

### Purpose

Records **which screen is shared** with the pair. It holds no content.

Content — the asset pool, the default asset, the manual-switch flag — lives on the screen
document (§3.5). This document only points at it:

```json
{
  "deviceId": "tg_f4ec6bb0ef83",
  "screenId": "screen_1770917521614",
  "ownerUid": "uid_1",
  "type": "IMAGE",
  "sharedAt": "serverTimestamp"
}

```

| Field | Type | Description |
| --- | --- | --- |
| `deviceId` | string | Device that owns the shared screen |
| `screenId` | string | The screen being shared |
| `ownerUid` | string | User who shared it |
| `type` | string | `IMAGE` or `ANIMATION`, uppercase |
| `sharedAt` | timestamp | When sharing was enabled |

### Why a pointer rather than the content

Holding several images on one screen is a property of *that screen*, not of a pair. Storing the
pool here would mean an unpaired user could never have more than one image on a screen. Keeping
content on the screen document also spares the device an extra REST round-trip for its own
screens.

The pointer is written together with the screen update in a single `WriteBatch`, so the two never
drift apart. Firestore has no foreign keys, so deleting a screen must also delete its pointer —
the screen document records `pairId` and `sharedScreenId` precisely so this cleanup is a direct
delete rather than a collection-group query.

The document id is deterministic: `{deviceId}_{screenId}`.

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

Document ids are `asset_{epochMillis}`.

```json
{
  "ownerUid": "Mafae7L0dxMvgxfVxjxmv0q1hbP2",
  "name": "heart",
  "type": "IMAGE",
  "width": 16,
  "height": 16,
  "encoding": "SPARSE_PACKED_V1",
  "pixelsPacked": "4700d9ff4900d9ff",
  "isDefault": false,
  "tags": [],
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}

```

| Field | Type | Description |
| --- | --- | --- |
| `ownerUid` | string | Creator. Security rules gate writes on this |
| `name` | string | Display name in the asset library |
| `type` | string | `IMAGE` or `ANIMATION` |
| `encoding` | string | `SPARSE_PACKED_V1` |
| `pixelsPacked` | string | Packed non-black pixels (see §4.4) |
| `isDefault` | boolean | Built-in asset shown in the "Default Assets" tab |

---

### 4.4 Static image asset: `SPARSE_PACKED_V1`

Non-black pixels are packed into **one string** of fixed-width 8-character groups. Each group is
`IIRRGGBB`:

- `II` — pixel index as 2 hex chars, `index = y*16 + x`, `00`–`FF`
- `RRGGBB` — colour as 6 hex chars

```
4700d9ff 4900d9ff
│ └─ colour 0x00d9ff   │ └─ colour 0x00d9ff
└─ index 0x47 = 71     └─ index 0x49 = 73
```

Black pixels are implicit and are not stored.

**Why a packed string:** the previous per-pixel format (`pixels: [{index, color}, ...]`) produced
Firestore documents around **23 KB**, which the device's Firebase client silently failed to
buffer — the screen rendered blank. The packed form is roughly **1 KB** for the same image.
See `_convertToPackedFormat` in `firebase_repository_impl.dart` and `AssetCache::parseAsset` on
the device.

> The older `SPARSE_I16_RGB888` encoding with a `pixels` array is **no longer written**. Assets in
> the live database all use `SPARSE_PACKED_V1`.

---

### 4.5 Animation asset: delta sparse frames

> **Unverified.** The live database currently contains no `ANIMATION` assets, so this section
> could not be checked against real data. Given static images moved to `SPARSE_PACKED_V1` for
> document-size reasons (§4.4), treat the format below as the original design rather than
> confirmed behavior, and re-check it against `AssetCache::parseAsset` before relying on it.

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
add/update/delete) and from `updateDevice()`. The asset path resolves which
devices to ring with three collection-group queries over `screens` -
`assetId`, `defaultAssetId` and `availableAssetIds` - since the asset pool
lives on the screen document.

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
3. Read each screen's own `availableAssetIds` / `defaultAssetId`. Only when a screen has an empty
   pool **and** carries both `pairId` and `sharedScreenId`, fall back to fetching
   `/pairs/{pairId}/sharedScreens/{sharedScreenId}`
4. Collect every referenced `assetId` — the whole pool, not just the default
5. Fetch required `/assets/{assetId}` documents
6. Build local cache (RAM; optional flash later)

Step 4 caches the entire pool so the action button can switch instantly and offline. If an asset
is somehow missing at render time, the device retries that one fetch, backing off 10 s between
attempts.

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

---

## 7. Known issues

Verified against the live `twinglow-bab2e` project. These are documented so they are not
rediscovered from scratch.

### 7.1 Pairing cannot complete — `pairingInvites` is denied by security rules

`sendPairingInvite()` writes to a top-level `pairingInvites` collection, but the deployed
Firestore rules contain **no `match` block for it**. Firestore denies anything unmatched, so
every invite write fails.

Consequences, in order:

1. no invite is ever stored;
2. `/pairs/{pairId}` is never created — the collection does not exist;
3. no screen ever gets a `pairId`;
4. the long-press "send to pair" action aborts with *"Cannot send to pair - no pair ID"*.

Fixing this needs a rules block for `pairingInvites` allowing the sender and the addressed
recipient. The `/pairs/**` rules themselves are already correct and require no change.

### 7.2 Send-to-pair has no receiver

`RtdbRepo::sendToPair()` pushes `{screenId, assetId, ts}` to RTDB `/pairs/{pairId}/events`.
**Nothing reads that path** — not the device, not the app. The send is write-only, so the
partner's device never displays what was sent. Two further problems in the same code: `ts` uses
`millis()` (device uptime, not epoch), so events cannot be ordered across devices or reboots; and
the return value is discarded, so the serial log reports success even on failure.

Note that `/pairs/{pairId}/events` is an RTDB path and is not listed in §5 — it exists only in
firmware.

### 7.3 Animation screens are created with type `image`

`screen_creation_view.dart` routes the Animation tile to the image editor, so an animation screen
is stored with `"type": "image"`.

### 7.4 Development-only security rules

`/devices/{deviceId}` and `/devices/{deviceId}/screens/{screenId}` are `allow read, write: if true`
— fully open, as the rules' own comments note. The device is unauthenticated and depends on this,
so tightening it requires giving the device a credential first.
