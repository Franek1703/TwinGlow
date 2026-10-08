# TwinGlow device firmware

ESP32 Arduino firmware for a 16×16 RGB pixel display, with local playlists, a clock, animations, sleep scheduling, and optional paired sharing.

[Project overview](../README.md) · [Mobile application](../twin_glow/README.md)

<p align="center">
  <img src="../readme_img/20261008_180313.jpg" width="280" alt="Two physical TwinGlow displays showing red and blue clocks" />
  <img src="../readme_img/20261008_180354.jpg" width="280" alt="Two physical TwinGlow displays showing pixel faces" />
</p>

## Capabilities and status

### ✅ Implemented

- 16×16 NeoPixel image rendering, looping animation playback, and a configurable digital clock.
- Ordered playlists with enabled/disabled screens, per-screen image/animation pools, and a default asset.
- Five debounced buttons for screen navigation, brightness, asset selection, sending, dismissal, and provisioning reset.
- BLE Wi-Fi provisioning, Firebase device authentication, and ownership-checked claiming.
- Firestore configuration/asset downloads and shared IMAGE/ANIMATION resolution.
- RTDB presence, pairing-state polling, immutable content snapshots, and display acknowledgments.
- NTP time synchronization, POSIX timezone rules, and a local daily dim/blank schedule.
- RAM asset caching and staged playlist updates that preserve the working content if downloads fail.
- Background cloud work with timeout/backoff/recovery handling.

### 🚧 In development / limitations

Sensor support is an in-development category. A concrete **Adafruit BME680** driver, capability detection, sensor rendering, and RTDB telemetry writes are present, but this is not a completed general external-sensor system. Sensor hardware is optional; its library is still needed to compile the current sketch.

Game screens, OTA firmware updates, and a general runtime command dispatcher are not implemented. `RtdbRepo` contains command helper methods, but the main loop does not execute a command queue. Screen auto-rotation is implemented behind a compile-time setting and is **disabled by default**.

## Hardware and wiring

The code targets the ESP32 Arduino platform. The documented CLI build uses `esp32:esp32:esp32` with the `huge_app` partition scheme. This is a software target, not confirmation of an exact board/module model.

| Connection | Default in `Config.h.example` |
| --- | --- |
| Matrix data | GPIO **2** |
| Matrix geometry | **16×16**, 256 RGB LEDs |
| LED protocol | `NEO_GRB + NEO_KHZ800`, NeoPixel/WS2812-compatible |
| Previous screen | GPIO **4** |
| Next screen | GPIO **5** |
| Brightness down | GPIO **18** |
| Brightness up | GPIO **19** |
| Action | GPIO **21** |
| Optional BME680 SDA / SCL | GPIO **22 / 23** |
| Optional BME680 I²C address | `0x76` |

Buttons use `INPUT_PULLUP` and active-low input: connect each button between its assigned GPIO and ground. Pixel rows are serpentine: even rows run left-to-right, odd rows right-to-left. A separate orientation transform applies to all renderers; the supplied setting is `PANEL_ORIENT_TRANSPOSE`.

Check [`Config.h.example`](Config.h.example) against your actual wiring before uploading. There is no full schematic, component BOM, panel part number, enclosure CAD, or verified voltage/current specification in the tracked project. Choose and verify the matrix power arrangement against the actual components; the GPIO table is not a complete assembly guide.

## Dependencies

Install the ESP32 Arduino board package and these libraries:

| Library | Used for |
| --- | --- |
| **FirebaseClient** by mobizt | Firebase Auth, Firestore, and Realtime Database |
| **ESP_SSLClient** by mobizt | TLS over a Wi-Fi socket with configurable buffers and CA verification |
| **ArduinoJson** | JSON parsing/serialization; the code uses the `JsonDocument` API |
| **Adafruit NeoPixel** | RGB matrix output |
| **Adafruit BME680 Library** | Optional sensor hardware path, including its required dependencies |

WiFi, BLE, Preferences, Wire, and FreeRTOS come from the ESP32 Arduino environment. The repository does not lock the complete board/library toolchain.

**FirebaseClient requires the repository's compatibility patches.** [`FirestoreRepo.h`](FirestoreRepo.h) deliberately fails compilation unless the payload-move, request-line, and document-mask-copy patch markers exist. The patch documentation records the FirebaseClient 2.2.13 compatibility work; an arbitrary library upgrade is not guaranteed to apply cleanly.

From the repository root, after installing the library:

```sh
bash tools/firebaseclient-patch/apply.sh
bash tools/firebaseclient-patch/apply.sh --check
```

The installer searches standard Arduino library locations and also accepts a library directory argument. It modifies the installed dependency, not the sketch. See the [patch README](../tools/firebaseclient-patch/README.md) for the memory, HTTP request, and pagination issues it addresses.

## Setup and enrollment

### 1. Prepare the Firebase project

Enable Email/Password Authentication, Firestore, and Realtime Database. Configure the mobile app for the same project and create the human owner's account. Rules and emulator configuration live in [`../firebase/`](../firebase/), not in the FlutterFire metadata file inside the app directory.

Install backend dependencies from `firebase/` with `npm ci`. Rules can be deployed from that directory with an explicit target:

```sh
firebase deploy --project=YOUR_FIREBASE_PROJECT_ID --only firestore:rules,database
```

Enrollment uses Firebase Admin Application Default Credentials in an administrator environment. Administrator credentials are never installed on the device or in the app.

### 2. Supply project configuration

From the repository root, copy the examples **only when the destination files do not already exist**:

```sh
cp -n TwinGlow/Config.h.example TwinGlow/Config.h
cp -n TwinGlow/FirebaseSecrets.h.example TwinGlow/FirebaseSecrets.h
```

Set these values in the local `FirebaseSecrets.h`:

```cpp
#define FIREBASE_API_KEY      "YOUR_FIREBASE_WEB_API_KEY"
#define FIREBASE_DATABASE_URL "https://YOUR_DATABASE_HOST"
#define FIREBASE_PROJECT_ID   "YOUR_FIREBASE_PROJECT_ID"
```

Use the exact RTDB URL from your project, including its region/instance hostname. Match GPIOs and panel orientation in `Config.h`.

Runtime authentication uses **a separately enrolled device email/password account**. [`PairingConfig.h`](PairingConfig.h) disables legacy-token mode even if an older local `Config.h` enables it. A project-wide database secret is not used by the current runtime. Older authentication documentation and comments describing that flow are historical.

### 3. Enroll this device for its owner

Each physical device needs its own stable ID, Auth credentials, and administrator-managed `deviceAccess/{deviceId}` entries in **both Firestore and RTDB**.

On a fresh board, boot the sketch far enough to initialize NVS and read `[NVS] Device ID` from serial at **115200 baud**. It is generated as `tg_` plus 12 hexadecimal characters and survives ordinary provisioning reset. An unenrolled initial build can reach provisioning but cannot authenticate to Firebase; that is expected. Do not erase NVS after recording the ID.

From `firebase/`, inspect a dry run using that ID and the actual owner's Firebase UID:

```sh
node enroll-device.mjs \
  --project YOUR_FIREBASE_PROJECT_ID \
  --database-url https://YOUR_DATABASE_HOST \
  --device YOUR_DEVICE_ID \
  --owner YOUR_OWNER_UID
```

To perform enrollment, repeat with:

```sh
node enroll-device.mjs \
  --project YOUR_FIREBASE_PROJECT_ID \
  --database-url https://YOUR_DATABASE_HOST \
  --device YOUR_DEVICE_ID \
  --owner YOUR_OWNER_UID \
  --apply \
  --credential-output /absolute/private/path/DeviceCredentials.h
```

The output parent directory must already exist and the destination file must be new. The script creates or rotates a device Auth password, assigns the `twinGlowDeviceId` claim, writes both access registries, and writes credentials to a private file with mode `0600`. Existing owner/identity mismatches fail enrollment.

Install that generated header as `TwinGlow/DeviceCredentials.h` for **that board only**, then rebuild. Do not reuse one device's credentials or compiled binary on another. The private credential and project settings headers are gitignored. Keep existing credentials when reflashing an already enrolled board; enrollment is not a required repeat step for every firmware update.

### 4. Build and upload

Open `TwinGlow.ino` in Arduino IDE, select the matching ESP32 target and partition scheme, and upload. Alternatively, from the repository root:

```sh
arduino-cli compile \
  --fqbn esp32:esp32:esp32:PartitionScheme=huge_app \
  TwinGlow

arduino-cli board list

arduino-cli upload \
  --fqbn esp32:esp32:esp32:PartitionScheme=huge_app \
  --port YOUR_SERIAL_PORT \
  TwinGlow
```

The `huge_app` target is the build configuration recorded in the implementation notes. Confirm it suits your actual hardware. Preserve NVS/device IDs when updating enrolled devices.

### 5. Provision Wi-Fi

Use the signed-in mobile app's **Settings → Add New Device** flow near the device. It writes UTF-8 SSID, password, and human owner UID to three characteristics under service `0000ff00-0000-1000-8000-00805f9b34fb`:

| Characteristic | Value |
| --- | --- |
| `0000ff01-0000-1000-8000-00805f9b34fb` | SSID, up to 32 bytes |
| `0000ff02-0000-1000-8000-00805f9b34fb` | Password, up to 64 bytes; empty for an open network |
| `0000ff03-0000-1000-8000-00805f9b34fb` | Human owner UID, up to 128 bytes |

The current app uses writes with response. After disconnect, firmware saves complete provisioning data, releases BLE, and reboots. It then joins Wi-Fi, synchronizes time, authenticates as the enrolled device, and creates device/membership records under the enrolled owner's UID. BLE transfer alone is not cloud enrollment or proof that claiming succeeded. Provisioning characteristics are not encrypted/bonded; perform setup in a trusted nearby environment.

## Buttons

| Control | Behavior |
| --- | --- |
| **PREV / NEXT**, short | Dismiss received content and move through enabled playlist screens. |
| **Brightness − / +**, short | Adjust brightness in steps of 16. Awake brightness persists locally and is queued for cloud write-back after a 1.5-second settling window. |
| **ACTION**, short on image/animation | Cycle the screen's asset pool if manual switching is allowed and more than one asset exists. |
| **ACTION**, short while receiving | Dismiss the received override and return to the playlist. |
| **ACTION**, held ~2.5 seconds | Send the selected cached image/animation if the screen is share-enabled and the device has an active pair. |
| **ACTION**, held ~10 seconds | Reset provisioning data and reboot. The device ID is retained; this does not unpair accounts or delete backend enrollment. |

During a sleep window, brightness buttons make a temporary adjustment for that window without overwriting awake brightness or the saved schedule. A zero sleep brightness blanks the panel. Clock/sensor screens have no short-ACTION operation.

## Runtime and synchronization

```text
Boot → load NVS → BLE setup if needed → Wi-Fi → NTP → Firebase Auth
     → claim device → detect capabilities → load configuration → local rendering
```

The main Arduino loop scans buttons, renders content, evaluates sleep, and consumes worker results. [`CloudWorker`](CloudWorker.cpp) serializes runtime Firebase work on a FreeRTOS task pinned to core 0. Boot setup and NTP attempts can still wait; the whole firmware is not strictly non-blocking.

| Activity | Supplied timing / behavior |
| --- | --- |
| Presence heartbeat | 20 seconds; writes `online` and `lastSeenMs` to RTDB. |
| Pair state / incoming snapshot check | About 5 seconds; reads `/config/{deviceId}` and can request a configuration check when its revision changes. |
| Firestore configuration / shared revision | 60-second scheduled fallback; loads settings, `configVersion`, and shared consent/version state. |
| Dedicated RTDB revision poll | `ENABLE_RTDB_DOORBELL` is `0`; the pair-state path above separately reads the revision. |
| NTP | Six hours after successful sync; failed/unsynced attempts use a five-minute retry cadence. |
| Sleep-window evaluation | Every 15 seconds using device local time; disabled when system time is invalid. |
| Optional sensor telemetry | 10 seconds when a BME680 capability is present; in development. |
| Automatic screen rotation | `SCREEN_AUTO_ROTATE` is `0`; if enabled, screen duration controls rotation and `durationMs <= 0` holds the screen. |

Intervals schedule attempts, not delivery guarantees. All cloud operations share one worker and can be delayed by downloads, transport timeouts, or recovery backoff.

Configuration reloads build a staging playlist, fetch required assets individually, reuse unchanged cached assets, and validate the versions before replacing the live playlist. Failed downloads leave the previous working playlist/cache intact. Shared authorization changes remove affected shared screens when observed.

## Pairing and received display

The mobile app creates pairing through RTDB email invitations, with one chosen device per user. Firestore shared content additionally requires both users' consent in `sharingPairs/{pairId}`.

Shared IMAGE/ANIMATION definitions live in `sharedScreens/{id}`. Each device keeps a content-free reference with its own order, enabled state, and duration; canonical pixel data remains in `assets/{assetId}`. Clock and sensor screens stay local. The device resolves shared screens and pools during configuration reloads; it does not continuously synchronize the selected screen or animation frame with its partner.

Long-ACTION sending uses a separate RTDB snapshot path:

```text
Selected cached asset → sender mailbox + recipient incoming metadata
                      → recipient polling/fetch → received display → acknowledgment
```

The snapshot contains the image or complete animation captured at send time, plus an event ID, persistent sequence, identities, and server timestamp. Later asset edits do not change that sent content. The receiver persists handled sequences to suppress duplicates across restarts and acknowledges `displayed` after rendering, or `rejected` for invalid/expired content.

There is one latest mailbox per sender, not a durable message queue. The latest pending local send wins; transient send retries expire after 60 seconds. Received events older than 24 hours are rejected. A blank sleep panel defers fetching/display; a dim but nonblank panel can receive. Received content holds until dismissed, superseded, or the pair changes and does not become a saved playlist asset.

## Content formats

| Type | Encoding and limits |
| --- | --- |
| Image | `SPARSE_PACKED_V1`: eight-character `IIRRGGBB` groups; 0–255 row-major pixel indices; at most 2,048 packed characters. |
| Animation | `DELTA_SPARSE_PACKED_V1`: packed first frame plus cumulative deltas; 2–16 frames, 50–5,000 ms per frame, at most 8,192 packed characters across base/deltas. Loops continuously. |
| Shared screen | IMAGE or ANIMATION with 1–10 matching asset IDs and a default within the pool. |
| Snapshot publication | Maximum 12,288-byte JSON publication budget. |

Older sparse image/animation encodings remain readable. New app saves use the packed formats. Pixels are transformed through one panel-orientation function and gamma-corrected before output. The physical device reads converted pixel data; it does not open GIF/PNG/WebP files itself.

Default library art is downloaded from Firestore, not compiled into the sketch. Missing/invalid assets show a dim red status indicator; an empty playlist or unsupported screen type uses a dim gray indicator.

## Persistence and offline behavior

| Persists in NVS | Held in RAM |
| --- | --- |
| Device ID, Wi-Fi credentials, provisioning state, claimed UID | Playlist definitions and current selection |
| Awake brightness, POSIX timezone, sleep settings | Image pixels and animation deltas |
| Outgoing sequence and last handled incoming sequence | Pending sends and received display override |

After a successful load, rendering and buttons continue locally through a network interruption while reconnection is attempted. The phone can be closed. RAM content is lost on restart; there is no persistent offline playlist/asset store. Cold boot without cloud access cannot restore the previous artwork, and an unsynchronized clock cannot reliably show time or enter scheduled sleep.

Recovery may deliberately reboot after a prolonged outage (the supplied Wi-Fi recovery threshold is 12 minutes after a prior connection), or a worker operation stuck for three minutes. Offline playback is therefore bounded by the running session, not an indefinite offline guarantee.

## Source guide

All sketch source files are directly in this directory; the module names below describe responsibilities, not nested folders.

| Files | Responsibility |
| --- | --- |
| `TwinGlow.ino`, `StateMachine.*`, `Scheduler.*` | Startup, state transitions, rendering orchestration, and periodic tasks. |
| `Config.h.example`, `PairingConfig.h` | Pins, timings, display options, and effective device-auth configuration. |
| `NvsStore.*` | Persistent identity, settings, provisioning, and delivery sequences. |
| `BleProvisioning.*`, `WifiManager.*` | BLE GATT setup and Wi-Fi connection/recovery. |
| `FirebaseClientWrap.*`, `FirebaseTypes.h`, `FirebaseRootCA.h` | Firebase services, per-device UserAuth, and TLS trust. |
| `CloudWorker.*`, `CloudMessages.h` | Serialized runtime cloud jobs and result transfer. |
| `FirestoreRepo.*`, `FirestorePagination.h`, `SharedScreenContract.h` | Configuration, assets, pagination, and shared references. |
| `RtdbRepo.*`, `PairingController.*`, `PairSnapshot.*`, `PairTransport.h` | Presence, paired snapshot transport, receive state, and acknowledgments. |
| `AssetCache.*`, `PlaylistUpdate.*`, `ScreenPlaylist.*` | RAM content, staged replacement, and navigation. |
| `MatrixDriver.*`, `RenderAsset.*`, `RenderClock.*`, `PixelFont.*` | LED mapping/output and pixel/clock rendering. |
| `TimeSync.*`, `SleepSchedule.*` | NTP, timezone rules, and sleep windows. |
| `Buttons.*`, `ButtonActions.*` | Input events and context-sensitive controls. |
| `Bme680Driver.*`, `RenderSensor.*` | In-development sensor path. |
| `FirebaseTest.*` | Optional diagnostic Firebase test, disabled by default. |

## Verification

After installing ArduinoJson and the patched FirebaseClient dependency, run from the repository root:

```sh
bash tools/firebaseclient-patch/apply.sh --check
python3 tools/firebaseclient-patch/test.py
bash tools/native-pairing/test.sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app TwinGlow
```

Native tests need Python 3 and a C++17 compiler with AddressSanitizer/UndefinedBehaviorSanitizer. `tools/native-pairing/test.sh` uses ArduinoJson from the default Arduino library directory or the `ARDUINOJSON_ROOT` environment variable. They exercise snapshot encoding/receiving, deduplication, playlist staging, asset parsing, Firestore pagination, transport reset, and sleep/brightness behavior with host stubs.

The combined `npm test` suite in `firebase/` additionally starts Firebase emulators and runs rules and Dart integration tests; see the [app verification prerequisites](../twin_glow/README.md#verification).

Hardware acceptance requires flashing **each board with its own credentials**, checking LED orientation/colors, cycling all pooled assets, editing shared content from both accounts, testing both-direction image/animation sends, observing display acknowledgments, and repeating with sleep, Wi-Fi loss, reboot, and unpairing. See the [shared-screen hardware procedure](../docs/shared_screens_implementation.md). Software builds and host stubs do not establish those physical results.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Compile error about required FirebaseClient patches | Apply/check all three SDK patches against the installed library and rebuild. |
| `[Firebase] Device not enrolled` | Install the correct generated `DeviceCredentials.h` and rebuild for that board. |
| Permission denied while claiming or reading | Match NVS device ID, device Auth claim, owner UID, and enabled registry entries in both databases; confirm rules/project selection. |
| Invalid clock / red clock status | Check Wi-Fi and NTP reachability. TLS certificate validation also needs a valid system clock. |
| Red image/animation indicator | Inspect asset fetch/parse logs, encoding, codec limits, and dependency patches. |
| Rotated/mirrored output | Match serpentine wiring and `PANEL_ORIENTATION` to the actual panel mounting. |
| New screen is not visible | Wait for a successful poll/download and press NEXT/PREV; rotation is disabled by default. |
| Cloud writes fail while art still plays | Check serial worker/backoff logs, Wi-Fi, TLS, free heap/largest allocation, and project access. Local rendering can continue with cloud I/O unavailable. |
| Pair send is ignored | Select a cached IMAGE/ANIMATION on a share-enabled screen, confirm active pairing, and leave received/blank-sleep modes first. |

The [pairing notes](../docs/pairing_implementation.md) and [shared-screen notes](../docs/shared_screens_implementation.md) contain detailed contracts and historical verification. Older device/authentication documents describe earlier implementations; the current source and this README take precedence for setup.
