# TwinGlow mobile application

The Flutter companion app for configuring a TwinGlow display, creating pixel content, and sharing it with another person. A single unpaired device has the same local screen and asset tools.

[Project overview](../README.md) · [Device firmware](../TwinGlow/README.md)

<p align="center">
  <img src="../readme_img/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-10-08%20at%2019.06.29.png" width="210" alt="TwinGlow playlist showing image and animation screens" />
  <img src="../readme_img/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-10-08%20at%2019.06.36.png" width="210" alt="TwinGlow mobile asset library" />
  <img src="../readme_img/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-10-08%20at%2019.06.51.png" width="210" alt="TwinGlow device brightness, sleep, and timezone settings" />
</p>

## What the app does

### ✅ Implemented

- **Accounts:** email/password sign-up, sign-in, session restoration, guarded navigation, and sign-out.
- **Onboarding and provisioning:** a locally remembered introduction, BLE discovery, and transfer of Wi-Fi credentials and the signed-in user's UID to the device.
- **Home / Screen Playlist:** device selection, content previews, screen creation/editing/deletion, enable toggles, and drag reordering.
- **Image and animation screens:** an ordered asset pool, a default asset, screen naming, and optional sharing. Browsing an app preview does not remotely select that asset on the physical device.
- **Asset library:** separate personal/default collections, asset names and tags, editing, and deletion of eligible personal assets.
- **Pixel editors:** drawing, erasing, area fill, color selection, clearing, and mirroring. Animation editing adds frame selection, duplication, deletion, reordering, per-frame duration, and playback preview.
- **Imports:** image selection/cropping/conversion and animation cropping/conversion, with Pixel Art and Photo modes. Imported content opens in an editor before it is saved.
- **Device settings:** name, online status, hardware capability display, brightness, timezone selection, and a sleep schedule with start/end times and sleep brightness.
- **Pairing:** email invitations, selection of owned devices, acceptance/rejection/cancellation, and unpairing. Shared IMAGE/ANIMATION screens are resolved inside the ordinary playlist.

### 🚧 In development / incomplete

The sensor editor can save metric, unit, and color settings, and firmware contains a BME680 path. The broader external-sensor feature remains in development. Game previews/models are placeholders. The forgot-password action, profile display-name save, and device-removal button still contain TODOs; repository methods alone do not make those UI flows complete.

## Stack and supported targets

| Area | Implementation |
| --- | --- |
| App | Flutter / Dart; package `twin_glow`, version `0.1.0` |
| Dart constraint | `^3.10.0`, as declared in [`pubspec.yaml`](pubspec.yaml) |
| State | `flutter_bloc` Cubits |
| Navigation | `go_router` with an authentication guard |
| Layout | Dark theme, shared widgets, and `flutter_screenutil` |
| Backend | `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_database` |
| Device setup | `flutter_blue_plus` |
| Media | `image`, `image_picker`, `file_selector`, `image_cropper` |
| Local state and timezones | `shared_preferences`, `flutter_timezone`, and a committed IANA-to-POSIX mapping |

Android and iOS native projects are included. There are no tracked web or desktop application targets. Use [`pubspec.lock`](pubspec.lock) for the resolved Dart package versions; no Flutter SDK version is pinned in this repository.

## Development setup

### Prerequisites

- A Flutter installation that supplies Dart compatible with the package constraint.
- Android SDK/JDK 17 for Android, or macOS with Xcode and CocoaPods for iOS.
- Firebase CLI and FlutterFire CLI available locally for project configuration.
- A Firebase project with **Email/Password Authentication**, **Cloud Firestore**, and **Realtime Database** enabled.
- A physical phone and an enrolled TwinGlow device for BLE provisioning and hardware verification. The provided screenshots demonstrate simulator UI, not simulator BLE support.

### Configure and run

From this directory:

```sh
flutter pub get
flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID --platforms=android,ios
flutter devices
flutter run -d YOUR_DEVICE_ID
```

Before `flutter run`, confirm the configuration files exist for the selected target:

| File | Purpose |
| --- | --- |
| `lib/firebase_options.dart` | Imported by `main.dart` to initialize Firebase. |
| `android/app/google-services.json` | Firebase configuration for the Android app. |
| `ios/Runner/GoogleService-Info.plist` | Firebase configuration for the iOS app. |

These files are gitignored. Obtain or generate configuration for your own registered apps, verify the package/bundle IDs match, and confirm that it selects the intended Realtime Database instance. The checked-in [`firebase.json`](firebase.json) describes an existing FlutterFire registration; it is not a substitute for these files or for backend rules deployment.

For iOS, install pods after resolving Flutter packages:

```sh
cd ios
pod install
```

Backend rules and emulator configuration live in [`../firebase/`](../firebase/). Run backend commands from that directory. An explicit rules deployment command for a configured project is:

```sh
firebase deploy --project=YOUR_FIREBASE_PROJECT_ID --only firestore:rules,database
```

Device ownership requires the administrative enrollment step in the [firmware README](../TwinGlow/README.md#setup-and-enrollment). BLE provisioning supplies Wi-Fi and a human UID; it does not create the device's Auth identity or grant ownership in the registries.

### First use

1. Sign up or sign in, with the same account UID used for device enrollment.
2. Open **Settings → Add New Device**, scan for TwinGlow, and send the Wi-Fi network details.
3. The device saves provisioning data, restarts, connects to Firebase, and creates its device/membership documents. Refresh the app's device list after this completes. The provisioning success message confirms the BLE transfer, not the subsequent cloud connection.
4. Select a device and add a clock, image, or animation screen. Create/import personal assets or select available default assets.
5. Set brightness, timezone, and sleep mode from Device Configuration.

The default asset tab queries Firestore documents with `isDefault: true`; there is no bundled production pixel-art pack or database seeding script. Sample content in `FirebaseFakeRepository` is test/demo data and is not loaded by the normal app entrypoint.

## Pairing and shared content

Open **Settings → Pairing Management** and invite the other account by email, choosing an owned enrolled device. The recipient accepts using their own device. Email lookup uses the RTDB pairing directory populated by the app; each account must have signed into the updated app. Invitations expire after seven days. Each account can have one active pair.

After pairing, both users must open the updated app so each can record their own Firestore sharing consent. Sharing an IMAGE/ANIMATION screen then creates a common screen definition and one local reference in each playlist. The pool contains **1–10 assets of the screen's type**.

- Either participant can change shared content and edit authorized shared assets.
- Order and enabled state belong to each device's local reference.
- Default templates remain immutable; publication makes editable personal copies when necessary.
- An asset reused by multiple screens updates all those references when edited.
- Concurrent shared-screen and asset edits use version checks; refresh/reopen after a conflict.
- Assets still referenced by shared screens cannot be deleted until removed from those screens.
- Stopping sharing restores the creator's private screen and removes the partner reference. Unpairing freezes sharing, cleans up shared screens, revokes consent, and ends RTDB pairing; retry if cleanup fails.

Physical **long-ACTION snapshot sending** is a separate firmware path. It sends the selected cached image or whole animation through RTDB and does not depend on the phone staying open. The mobile app is not a chat-history or direct-send interface.

## Data flow

```text
Views → feature Cubits → repository/services → Firebase client SDKs
                                        └──→ BLE repository → ESP32 setup
```

[`FirebaseRepositoryImpl`](lib/services/firebase/firebase_repository_impl.dart) is used by the application. Fake Firebase and BLE implementations exist for isolated tests. The active shared-playlist implementation is [`SharedFirestoreService`](lib/services/firebase/shared_firestore_service.dart); the older RTDB `SharedScreensService` preview catalog remains in the tree but is no longer the production playlist sharing model.

| Store | Important paths and data |
| --- | --- |
| Firebase Auth | Human email/password accounts; separate enrolled device identities. |
| Firestore | `users/{uid}`, `users/{uid}/devices/{deviceId}`, `devices/{deviceId}`, `devices/{deviceId}/screens/{screenId}`, `assets/{assetId}`. |
| Firestore sharing | `sharingPairs/{pairId}` for consent/versioning, `sharedScreens/{id}` for common content, `playlistState/{deviceId}` for append ordering. |
| Both databases | `deviceAccess/{deviceId}` is an administrator-managed ownership/device-identity registry. |
| RTDB | `pairing/` for invitations, membership, mailboxes and acknowledgments; `config/{deviceId}` for pair/incoming/revision data; `presence/{deviceId}` and the in-development `telemetry/{deviceId}` path. |
| Local preferences | Onboarding completion. |

Settings and local playlist writes advance Firestore `configVersion`. The app also writes a best-effort RTDB revision hint. Shared edits advance the sharing revision. ESP32s poll and download the resulting documents; app snapshot listeners do not turn device playback into a live Firebase subscription. Presence is normally written every 20 seconds, with a 60-second freshness window and periodic app-side rechecks.

Assets store pixel data directly in Firestore. There is no `firebase_storage` dependency or Cloud Functions service in this app.

## Asset formats and limits

Images become a 16×16 grid, encoded as `SPARSE_PACKED_V1`. Each eight-character `IIRRGGBB` group holds a pixel index (`y * 16 + x`) and RGB color.

Animations use `DELTA_SPARSE_PACKED_V1`: a complete first frame plus cumulative changes, with `000000` clearing a pixel. Playback loops.

| Constraint | Value |
| --- | --- |
| Animation frames | 2–16 |
| Frame duration | 50–5,000 ms; editor controls use 50 ms steps |
| Packed animation data | At most 8,192 characters across base and deltas |
| Shared screen pool | 1–10 matching image or animation assets |
| Import file size | At most 50 MiB as enforced by the import services |
| Image file picker | PNG, JPG/JPEG, WebP |
| Animation file picker | GIF, animated WebP, PNG/APNG |

Animation import can reduce frames or duration to fit the device format and shows an optimization notice. Saving validates the codec limits. The device consumes converted pixel data rather than decoding source image files. See [`animation_codec.dart`](lib/core/codecs/animation_codec.dart), [`asset_document.dart`](lib/services/firebase/asset_document.dart), and the [firmware format notes](../TwinGlow/README.md#content-formats).

## Source guide

```text
lib/
├── main.dart                 # Firebase and local onboarding initialization
├── app.dart                  # App, theme, shared auth state, and router
├── config/                   # Routing and visual tokens
├── core/
│   ├── codecs/               # Packed animation format
│   ├── models/               # Device, screen, asset, user, and pairing models
│   ├── utils/                # Brightness, presence, sleep, and timezones
│   └── widgets/              # Pixel editors, previews, and playlist UI
├── features/*/cubit/         # Feature state and operations
├── services/                 # Firebase, BLE, imports, and local preferences
└── views/                    # App pages and editors
test/                         # Unit, widget, and emulator integration tests
android/                      # Android host
ios/                          # iOS host
```

An ignored `Design TwinGlow Mobile UI/` React/Vite design export may be present in a local checkout. It is a visual reference, not the Flutter app or a required build dependency, and is not tracked in the repository.

## Verification

From this directory, after restoring dependencies and Firebase configuration:

```sh
flutter analyze
flutter test
```

Tests cover codecs, image/animation imports, editors, playlist changes, authentication routing, brightness/sleep/timezone behavior, pairing, and shared-screen operations. The pairing emulator test skips when emulator environment variables are absent.

For the combined backend/native/Dart integration suite, use a C++ compiler with ASan/UBSan support, Python 3, ArduinoJson and the patched FirebaseClient installation, Flutter, Node/npm, Firebase CLI, and a Java runtime compatible with its emulators. From `../firebase/`:

```sh
npm ci
npm test
```

This starts Auth, RTDB, and Firestore emulators for `demo-twinglow`. [`run-tests.mjs`](../firebase/run-tests.mjs) also runs SDK patch tests, native firmware tests, and the production Dart pairing service against emulator rules. The normal app does not automatically switch to emulators when this command is run.

For optional build checks from this directory:

```sh
flutter build apk --debug
flutter build ios --simulator
```

Builds and fake-repository tests do not validate physical BLE, LED output, or two-device delivery. Exercise pairing, both-direction animation delivery, shared edits, sleep, reconnects, and unpairing on real hardware as described in the [implementation checklist](../docs/shared_screens_implementation.md).

## Troubleshooting and current limits

| Symptom | Check |
| --- | --- |
| Missing `firebase_options.dart` or native Firebase setup | Generate/restore the ignored configuration for the target app and project. |
| Provisioned device does not appear | Confirm successful device cloud logs, matching owner UID/device ID in both registries, membership under `users/{uid}/devices`, and correct rules. |
| Device discovery fails | Use a real phone, enable Bluetooth, allow platform permissions, and make sure the device is advertising its provisioning service. BLE uses unencrypted characteristic writes; set it up in a trusted nearby environment. |
| Sharing asks to open both apps | Both accounts must establish their own Firestore consent before publication. |
| Default library is empty | Check for authenticated access and `isDefault: true` assets in the selected project. |
| Old personal assets are missing | Current queries use `ownerUid` and `isDefault: false`; legacy ownership requires the administrator-verified migration described in the pairing notes. |
| App preview changed but device has not | Allow polling/download time, inspect device network/config logs, and use NEXT/PREV to select an added screen. |

This is a development app: Android still has the example application ID and debug signing for release builds. The main Android manifest also lacks an explicit INTERNET permission (debug/profile manifests supply it), so release networking configuration needs review. Verify platform/plugin permissions and distribution configuration before shipping. Fully offline app workflows are not implemented; several operations explicitly require server reads and transactions.

[Pairing details](../docs/pairing_implementation.md) · [Shared screens v2](../docs/shared_screens_implementation.md)
