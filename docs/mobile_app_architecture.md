# TwinGlow Mobile Application

## Architecture & Code Structure

This document describes the **architecture, project structure, state management approach, routing model, and runtime flow** of the TwinGlow mobile application built with **Flutter**.

The application follows a **feature-based architecture**, with clear separation of concerns and scalable structure prepared for Firebase and BLE integration.

---

# 1. High-Level Architecture

The TwinGlow mobile app is built using:

* **Flutter (UI layer)**
* **GoRouter (navigation)**
* **flutter_bloc (Cubit-based state management)**
* **flutter_screenutil (responsive scaling)**

The app uses a **feature-based architecture**, meaning:

* Each business domain is isolated in its own feature module.
* UI, state management, models, and repositories are grouped by feature.
* Shared services (Firebase, BLE) are abstracted behind repository interfaces.
* The app is scalable and testable.

---

# 2. Core Architectural Principles

## 2.1 Feature-Based Structure

Each major business domain has its own folder:

```
features/
  device/
  screens_playlist/
  screen_editor/
  assets_library/
  asset_editor/
  pairing/
  auth/
```

Each feature contains:

```
feature_name/
  cubit/
  repository/
  widgets/
  models/
```

This ensures:

* Encapsulation of logic
* Low coupling between features
* Clear boundaries
* Easy future refactoring

---

## 2.2 Layered Responsibility Model

The architecture is divided into layers:

### 1️⃣ Presentation Layer

* Views
* Feature widgets
* UI components
* ScreenUtil scaling

### 2️⃣ State Layer

* Cubits (flutter_bloc)
* Immutable states
* Mock data (for now)

### 3️⃣ Repository Layer

* Abstract repository interfaces
* Fake implementations (temporary)
* Later: Firebase + BLE implementations

### 4️⃣ Service Layer

* Firebase communication abstraction
* BLE communication abstraction
* Centralized reusable services

---

# 3. Project Structure

```
lib/
  main.dart
  app.dart

  config/
    app_theme.dart
    app_colors.dart
    app_typography.dart
    app_spacing.dart
    app_router.dart
    env.dart

  core/
    models/
    widgets/
    utils/

  services/
    firebase/
      firebase_repository.dart
      firebase_fake_repository.dart
    ble/
      ble_repository.dart
      ble_fake_repository.dart

  views/
    onboarding/
    auth/
    home/
    assets/
    settings/

  features/
    device/
    screens_playlist/
    screen_editor/
    assets_library/
    asset_editor/
    pairing/
```

---

# 4. Libraries Used

## 4.1 go_router

Used for:

* Declarative routing
* Deep linking support
* Nested navigation (ShellRoute)
* Typed route parameters

Example routes:

```
/onboarding
/auth/login
/home
/device/:deviceId
/screen/:deviceId/:screenId
/assets
/settings
```

Navigation is fully declarative and centralized in `app_router.dart`.

---

## 4.2 flutter_bloc (Cubit)

Used for:

* Local state management
* UI-driven business logic
* Reactive rebuilds

Why Cubit and not full Bloc?

* Simpler
* Cleaner
* Less boilerplate
* Perfect for UI-driven state

Each feature owns its Cubit:

Example:

```
DevicesCubit
ScreensPlaylistCubit
AssetsCubit
ScreenEditorCubit
PairingCubit
AuthCubit
```

---

## 4.3 flutter_screenutil

Used for:

* Device-independent scaling
* Responsive layouts
* Consistent spacing and typography

All dimensions use:

```
16.w
12.sp
24.h
```

No hardcoded pixel values.

---

# 5. Application Flow

## 5.1 Launch Flow

1. App starts
2. Initialize ScreenUtil
3. Initialize GoRouter
4. Check authentication state

Flow:

```
If not authenticated:
    → Onboarding
    → Login / Register

If authenticated:
    If user has no devices:
        → Device Provisioning
    Else:
        → Home
```

---

## 5.2 Onboarding Flow

Purpose:

* Explain product
* Explain BLE provisioning
* Introduce sharing concept

Steps:

1. Intro screen
2. Feature explanation
3. Device setup CTA

After completion:
→ Auth screen

---

## 5.3 Authentication Flow

Email/password authentication.

Managed by:

```
AuthCubit
```

After login:

```
→ Fetch user devices
→ Navigate to Home or Device Setup
```

---

## 5.4 Home Flow

Home screen contains:

### Top Device Header

* Device name
* Online/offline indicator
* Small device icon
* Clickable → Device details screen

### Vertical Screen Playlist

Displays screens vertically:

* Clock
* Image
* Animation
* Sensor
* Game (future)

Each tile shows:

* Preview placeholder
* Duration
* Enabled toggle
* Shared badge (if `isShared == true`)

Shared badge does NOT show with whom.
Details visible only in screen editor.

---

## 5.5 Screen Editor Flow

When user taps a screen tile:

```
/screen/:deviceId/:screenId
```

Screen editor allows:

* Editing screen configuration
* Selecting asset
* Toggling shared mode
* Adjusting duration
* Configuring colors (clock, sensor)

Managed by:

```
ScreenEditorCubit
```

---

## 5.6 Assets Flow

Assets page contains:

Tabs:

* My Assets
* Default Assets

User can:

* View assets
* Create new asset
* Edit asset
* Delete asset

Asset editor supports:

* Pixel grid editing (16×16)
* Color selection
* Frame-based animation editing, in a dedicated editor reached by asset type
* Preview — static for images, looping for animations

Managed by:

```
AssetsCubit
AssetEditorCubit        // images
AnimationEditorCubit    // animations
```

---

## 5.7 Settings Flow

Settings include:

* Brightness preference (if local app config)
* Sleep mode schedule
* Pair management
* Logout
* Device rename
* Firmware version display

---

# 6. State Management Strategy

Each feature owns its state.

Example:

```
ScreensPlaylistState
  - List<ScreenModel>
  - isLoading
  - errorMessage
```

State is immutable.

Cubits:

* Expose pure methods
* Emit new state objects
* No UI logic inside Cubit

UI subscribes via:

```
BlocBuilder
BlocListener
```

---

# 7. Repository Abstraction

Currently:

* Fake repositories
* Mock data
* No Firebase connection yet

Structure:

```
abstract class FirebaseRepository
class FirebaseFakeRepository implements FirebaseRepository
```

Later:

* Real Firebase implementation
* Replace fake in DI layer

Same for BLE:

```
BleRepository
BleFakeRepository
```

---

# 8. Responsiveness Strategy

Using ScreenUtil:

* Fonts scale with `.sp`
* Width/height with `.w`, `.h`
* Padding uses spacing tokens

All theme values centralized in:

```
config/app_theme.dart
config/app_colors.dart
config/app_typography.dart
config/app_spacing.dart
```

---

# 9. Offline Readiness

The architecture is prepared for:

* Local caching
* Offline-first device interaction
* Deferred synchronization

Current mock structure already separates UI from backend.

---

# 10. Future Integration Points

The architecture supports:

* Firebase Firestore
* Firebase Realtime Database
* BLE device provisioning
* Shared screens synchronization
* Real-time updates

Integration points are isolated in:

```
services/firebase/
services/ble/
```

No feature directly depends on Firebase SDK.

---

# 11. Design Decisions Summary

| Decision                        | Reason               |
| ------------------------------- | -------------------- |
| Feature-based architecture      | Scalability          |
| Cubit over Bloc                 | Simplicity           |
| GoRouter                        | Clean navigation     |
| ScreenUtil                      | Responsive UI        |
| Repository abstraction          | Backend independence |
| Fake repositories first         | Faster UI iteration  |
| Shared badge only on tile       | Cleaner UX           |
| Detailed sharing info in editor | Context clarity      |

---

# 12. Architectural Benefits

This architecture provides:

* Clean separation of concerns
* Easy backend replacement
* Modular feature scaling
* Predictable state management
* Testable business logic
* Maintainable large codebase
