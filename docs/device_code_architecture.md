# ESP32 Firmware – Code Architecture & Full Runtime Flow

This document defines the recommended **firmware code structure** and the **complete execution flow** for the TwinGlow device (ESP32), including provisioning, Firebase connectivity, screen rendering, time sync, buttons, offline behavior, and error handling.

---

## 1. Architecture Goals

The firmware is designed to be:

- **Cloud-driven**: screens + assets come from Firebase (Firestore), while runtime signals use RTDB.
- **Offline-first**: device keeps running using cached config/assets if Wi-Fi or Firebase drops.
- **Non-blocking**: rendering and input must stay responsive even during network operations.
- **Deterministic**: state machine controls transitions; retries use backoff.
- **Extensible**: new screens (e.g., GAME) and new commands can be added without rewriting the core.

---

## 2. Recommended Project Structure (Modules)

A clean Arduino/PlatformIO structure (logical modules) can look like this:

```
/TwinGlow/
  TwinGlow.ino                  // main entry point, state handlers

  core/
    StateMachine.h/.cpp         // global device FSM (DeviceState enum)
    Scheduler.h/.cpp            // periodic jobs (presence, config poll, telemetry, ntp)

  storage/
    NvsStore.h/.cpp             // Preferences wrapper (ssid/pass/deviceId/uid/brightness)

  net/
    WifiManager.h/.cpp          // connect/reconnect, captive failures, retry/backoff
    BleProvisioning.h/.cpp      // GATT service, receive SSID/pass/uid, commit to NVS

  firebase/
    FirebaseClientWrap.h/.cpp   // init auth, Firestore ops, RTDB ops
    FirebaseTypes.h             // type aliases for FirebaseClient
    FirebaseTest.h/.cpp         // optional test functions
    FirestoreRepo.h/.cpp        // screens/assets/devices read/write
    RtdbRepo.h/.cpp             // presence/telemetry/commands (fields set individually)
    TimeSync.h/.cpp             // NTP sync + scheduling + app.setTime()

  ui/
    MatrixDriver.h/.cpp         // NeoPixel mapping, brightness, primitives
    RenderClock.h/.cpp          // procedural CLOCK screen renderer
    RenderSensor.h/.cpp         // procedural SENSOR (BME680) renderer
    RenderAsset.h/.cpp          // IMAGE/ANIMATION renderer from cached assets
    ScreenPlaylist.h/.cpp       // ordered list of screens, current index, duration
    AssetCache.h/.cpp           // cache for parsed asset data (pixels/frames)

  input/
    Buttons.h/.cpp              // debounce, short/long/very long press events
    ButtonActions.h/.cpp        // map events to behavior per screen type

  sensors/
    Bme680Driver.h/.cpp         // detect + read sensor, smoothing, units

  Config.h                      // build flags, pins, timing constants, secrets
  FirebaseSecrets.h.example     // template for Firebase credentials
```

**Why this structure works well:**

- You isolate *network* from *rendering* from *input*, so NeoPixel timing issues don’t break Wi-Fi/Firebase and vice versa.
- “Repository” style for Firestore/RTDB makes it obvious what data is read/written.
- A single global FSM prevents spaghetti logic.

---

## 3. Core Runtime State Machine (Global FSM)

### 3.1 States

1. **BOOT**
2. **LOAD_NVS**
3. **PROVISIONING_BLE**
4. **WIFI_CONNECTING**
5. **TIME_SYNC**
6. **FIREBASE_CONNECTING**
7. **DEVICE_CLAIMING**
8. **CAPABILITY_DETECT**
9. **CONFIG_LOADING**
10. **RUNNING**
11. **OFFLINE_RUNNING**
12. **ERROR_RECOVERY**

This matches your intended flow: BLE → Wi-Fi → NTP → Firebase → claim → detect BME680 → load config/assets → local scheduler loop.

---

## 4. Data Ownership in Firmware (What is Stored Where)

### 4.1 NVS (persistent, device-local)

Store:

- `wifiSsid`, `wifiPass`
- `deviceId` (generated once, stable forever)
- `provisioned` flag
- `claimedUid` (from BLE provisioning)
- `brightness` (persists between reboots)

### 4.2 RAM cache (volatile)

Store:

- Screen playlist (enabled screens + order)
- Asset cache (decoded pixels/frames)
- Current screen index + elapsed timer
- Sensor latest readings
- Last successful sync timestamps (NTP, configVersion, presence push)

### 4.3 Firebase (remote)

- Firestore: configuration + assets (source of truth)
- RTDB: presence/telemetry/commands (ephemeral live data)

---

## 5. Full Program Flow (All Cases)

### 5.1 Boot Sequence

**BOOT → LOAD_NVS**

1. Initialize Serial, pins, NeoPixel driver (safe defaults).
2. Load NVS keys.
3. If `deviceId` missing → generate random ID → store in NVS.

**Decision: provisioning needed?**

- If SSID/pass missing → go **PROVISIONING_BLE**
- Else → go **WIFI_CONNECTING**

---

### 5.2 BLE Provisioning (PROVISIONING_BLE)

Device starts BLE GATT service exposing characteristics for:

- SSID
- password
- Firebase `uid` (from mobile app)
- “commit/provision” command

**Success path**

1. App writes SSID/pass/uid.
2. Device validates payload (non-empty, max length, UTF-8 sanity).
3. Save to NVS: `wifiSsid`, `wifiPass`, `claimedUid`, `provisioned=true`.
4. Stop BLE, proceed to **WIFI_CONNECTING**.

**Failure cases**

- Invalid payload → keep BLE, expose error status characteristic (optional)
- Provision timeout (e.g., 5–10 min) → keep BLE or restart BLE advertising
- User triggers “reset provisioning” (very long press) → clear NVS and stay in BLE mode

---

### 5.3 Wi-Fi Connection (WIFI_CONNECTING)

1. Attempt Wi-Fi connect using NVS credentials.
2. Use retry policy:
    - e.g., 5 quick retries
    - then exponential backoff (5s → 10s → 30s → 60s)

**Success**

- Transition to **TIME_SYNC**

**Failure**

- If repeated failures exceed threshold → return to **PROVISIONING_BLE** (network likely changed)

**Special cases**

- Wi-Fi connected but DNS/TLS failing: treat as “connected but no internet”, continue to TIME_SYNC but allow failure path to OFFLINE_RUNNING.

---

### 5.4 Time Sync (TIME_SYNC)

ESP32 has no battery-backed RTC, so CLOCK requires external sync.

**Policy (as you defined):**

- Sync on boot after Wi-Fi connects
- Re-sync every **6 hours**

**Implementation concept**

- Call NTP helper to obtain epoch time
- Apply to Firebase client via:
    - `app.setTime(get_ntp_time());`

**Success**

- Store `lastNtpSyncMs = millis()`
- Move to **FIREBASE_CONNECTING**

**Failure**

- If NTP fails:
    - continue with last known system time
    - proceed anyway (Firebase may still work if TLS accepts current time; if not, Firebase connection will fail and you’ll fall back to OFFLINE_RUNNING)
    - schedule another attempt in e.g. 1–5 minutes

---

### 5.5 Firebase Connection (FIREBASE_CONNECTING)

Firebase auth model:

- Uses **legacy RTDB Database Secret** via `ServiceAuth` (device-level auth, not user auth).

**Steps**

1. Initialize Firebase client with:
    - Web API Key
    - RTDB URL
    - Database Secret (ServiceAuth)
2. Verify connectivity with a lightweight call (e.g., read a small RTDB node).

**Success**

- Transition to **DEVICE_CLAIMING**

**Failure**

- Reasons:
    - wrong API key / DB secret
    - project auth not enabled (HTTP 400)
    - TLS fails due to incorrect device time
    - no internet
- Action:
    - go to **OFFLINE_RUNNING**
    - keep retrying Firebase connect periodically in the background (e.g., every 30–120s with backoff)

---

### 5.6 Device Claiming (DEVICE_CLAIMING)

Goal:

- Ensure `/devices/{deviceId}` exists
- Ensure `/users/{uid}/devices/{deviceId}` membership exists (automatic claiming)

**Inputs**

- `deviceId` from NVS
- `claimedUid` from NVS (received via BLE)

**Success path**

1. Check `/devices/{deviceId}`.
2. If missing → create it with metadata (`fwVersion`, `hw.matrix`, etc.).
3. Create membership doc `/users/{claimedUid}/devices/{deviceId}`.

**Failure cases**

- `claimedUid` missing:
    - device can still run in “unclaimed mode” locally
    - but should request provisioning again (BLE) OR show a special “pair me” screen
- Firestore write fails:
    - keep running offline
    - retry claiming later

---

### 5.7 Capability Detection (CAPABILITY_DETECT)

1. Attempt to init BME680.
2. Determine `bmePresent=true/false`.
3. Read current state from Firestore.
4. Only update Firestore if changed (avoid extra writes).

**Failure cases**

- Sensor init fails intermittently:
    - treat as “not present” unless confirmed stable
    - optionally re-check every few minutes

---

### 5.8 Configuration & Assets Load (CONFIG_LOADING)

**Trigger conditions**

- First boot after Firebase connected
- `configVersion` changed
- command `RELOAD_CONFIG` received (optional RTDB command)

**Load steps**

1. Read `/devices/{deviceId}.configVersion`
2. Fetch `/devices/{deviceId}/screens` ordered by `order`
3. From enabled screens, collect referenced assets:
    - for IMAGE/ANIMATION: `defaultAssetId`, `availableAssetIds`
4. Fetch `/assets/{assetId}` docs
5. Build local caches

**Failure cases**

- Firestore temporarily unavailable:
    - keep existing cached config/assets
    - continue in OFFLINE_RUNNING
- Asset doc missing / corrupted:
    - skip that asset
    - render fallback (blank or built-in “error icon”)
    - do not crash the scheduler

---

### 5.9 Running Loop (RUNNING / OFFLINE_RUNNING)

Once the device has at least one valid playlist (from cache or fresh load), it enters the steady state.

### Core loops that run concurrently (cooperatively in `loop()` or via tasks/timers)

1. **Screen Scheduler**
    - rotates screens by `durationMs`
    - supports manual navigation (◀ ▶)
2. **Renderer**
    - CLOCK: procedural render using local time + Firestore-provided colors/config
    - SENSOR: procedural render using BME680 + colors/config
    - IMAGE/ANIMATION: render cached assets
3. **Button Handler**
    - debounced events
    - short/long/very long actions
4. **Periodic Jobs** (managed by `Scheduler` class)
    - RTDB presence update (every 20 seconds)
    - optional telemetry push (every 10 seconds, only if BME680 present)
    - configVersion polling (every 60 seconds)
    - NTP resync every 6 hours
    - All tasks check Wi-Fi connectivity before executing
    - Failed operations are logged but don't block device operation

---

## 6. Button-Driven Runtime Flow (5 Buttons)

Buttons are final and consistent across screens.

### 6.1 Global actions

- ◀ / ▶: previous/next screen (wrap-around)
- − / +: brightness down/up (down to 0), persist to NVS

### 6.2 Context actions (● Action)

- CLOCK: no action
- SENSOR: no action
- IMAGE / ANIMATION:
    - short press: switch to next available asset in `availableAssetIds`
    - long press (2–3s): “send to paired user” when screen is shared
- Very long press (~10s): clear Wi-Fi creds and re-enter BLE provisioning

**Implementation note**

- The Action button should emit events (`SHORT`, `LONG`, `VERY_LONG`) to a single handler that routes behavior by current screen type.

---

## 7. “Send to Pair” Behavior (Device Side)

When the user long-presses ● on a shared IMAGE/ANIMATION screen, device should:

1. Determine current screen + currently selected `assetId`
2. Write a small “share event” to RTDB (recommended) OR update Firestore shared content (depending on your final schema)
3. Optionally show visual feedback (blink animation)

Even if sharing fails (offline):

- keep selection locally
- queue a retry (optional) or show failure indicator

*(This is consistent with your separation of Firestore for config and RTDB for live events.)*

---

## 8. Robustness & Edge Cases (Checklist)

### 8.1 Device has no Wi-Fi creds

- Enter BLE provisioning (always recoverable)

### 8.2 Wi-Fi creds are wrong (router changed)

- Retry with backoff
- After threshold → BLE provisioning

### 8.3 Firebase is down / no internet

- Enter OFFLINE_RUNNING
- Keep cached playlist/assets
- Retry Firebase periodically

### 8.4 NTP fails

- Continue running with local time drift
- Retry later
- If TLS requires correct time, Firebase may fail; still keep device running offline

### 8.5 Config/asset fetch partially fails

- Keep old cache
- Skip missing assets and render fallback
- Never block UI or crash

### 8.6 BME680 absent but SENSOR screen exists

- Render “no sensor” placeholder or hide SENSOR screens by marking them disabled at config-level (your choice)
- Still keep scheduler running

### 8.7 NeoPixel timing vs Wi-Fi

- Keep rendering FPS low
- Avoid long blocking network calls during `strip.show()`
- Prefer “small chunks” of network work between frames

---

## 9. Minimal Periodic Task Schedule (Actual Implementation)

- Presence push (RTDB): every **20 seconds** (`PRESENCE_UPDATE_INTERVAL_MS = 20000`)
- Telemetry push (optional): every **10 seconds** (`TELEMETRY_UPDATE_INTERVAL_MS = 10000`) - only if BME680 present
- ConfigVersion poll (Firestore): every **60 seconds** (`CONFIG_POLL_INTERVAL_MS = 60000`)
- NTP resync: every **6 hours** (`NTP_SYNC_INTERVAL_MS = 21600000`)

**Implementation Details:**
- All periodic tasks are managed by the `Scheduler` class
- Tasks are registered during `CONFIG_LOADING` state
- Tasks check connectivity before executing (Wi-Fi must be connected)
- Failed operations are logged but don't block device operation
- Telemetry updates are only scheduled if BME680 sensor is detected

---

## 10. Final “One-Page” Execution Summary

1. Boot → load NVS (deviceId, Wi-Fi, uid, brightness)
2. If no Wi-Fi → BLE provisioning
3. Connect Wi-Fi (retry/backoff)
4. NTP sync now + schedule every 6h
5. Connect Firebase (ServiceAuth DB secret)
6. Claim device for uid (create device doc + membership)
7. Detect BME680 presence (update Firestore only if changed)
8. Load screens + assets, build cache
9. RUNNING: local scheduler + renderer + buttons + periodic syncs
10. If offline: OFFLINE_RUNNING using cached data, keep retrying network