# Physical Button Interface

This document defines the **physical button layout**, **interaction model**, and **runtime behavior** of the TwinGlow device.

The goal is to provide a **simple, intuitive, and robust** on-device control system that works consistently across all screen types while remaining easy to implement in firmware.

---

## 1. Design Goals

The physical interface is designed to:

- Be intuitive without instructions
- Avoid button combinations or hidden gestures
- Minimize firmware complexity
- Support all required features (navigation, brightness, content control)
- Scale well with future features (games, interactions)

The device uses **five physical buttons**, which is considered the optimal balance between usability and hardware complexity.

---

## 2. Button Layout

Recommended physical layout:

```
[ ◀ ]   [ ▶ ]
[ − ]   [ + ]
[   ●   ]
```

- Directional buttons are grouped visually
- Brightness controls are clearly separated
- Center button is the primary action button

---

## 3. Button Definitions

| Button | Symbol | Primary Purpose |
| --- | --- | --- |
| Previous | ◀ | Navigate to previous screen |
| Next | ▶ | Navigate to next screen |
| Brightness Down | − | Decrease LED brightness |
| Brightness Up | + | Increase LED brightness |
| Action | ● | Context-dependent action |

---

## 4. Global Button Behavior

These actions apply **regardless of the active screen**.

### 4.1 Screen Navigation

- **◀ (Previous)**
    
    Moves to the previous screen in the device playlist.
    
- **▶ (Next)**
    
    Moves to the next screen in the device playlist.
    

Navigation wraps around at the beginning and end of the playlist.

---

### 4.2 Brightness Control

- **− (Brightness Down)**
    
    Decreases LED brightness in discrete steps.
    
- **+ (Brightness Up)**
    
    Increases LED brightness in discrete steps.
    

Notes:

- Brightness can be reduced down to **0** (display off).
- Brightness changes affect **all screens globally**.
- Brightness level is stored locally (NVS) and persists across reboots.

---

## 5. Context-Dependent Button Behavior (Action Button ●)

The **Action (●)** button performs different actions depending on the active screen type.

---

### 5.1 CLOCK Screen

- **● (short press)**
    
    No action.
    

Rationale:

- Clock is fully automatic and informational.
- Avoids accidental mode changes.

---

### 5.2 SENSOR Screen (BME680)

- **● (short press)**
    
    No action.
    

Rationale:

- Sensor screen reflects live data.
- No meaningful user-initiated interaction.

---

### 5.3 IMAGE Screen

- **● (short press)**
    
    Switch to the next available image in the screen’s local asset pool.
    
- **● (long press, ~2–3 seconds)**
    
    Send the currently displayed image to the paired user (if the screen is marked as `sharedWithPair = true`).
    

Behavior notes:

- Image switching is local and offline-safe.
- Sending content is always an explicit long-press action.
- No automatic or accidental sharing occurs.

---

### 5.4 ANIMATION Screen

- **● (short press)**
    
    Switch to the next available animation.
    
- **● (long press, ~2–3 seconds)**
    
    Send the currently active animation to the paired user (if shared).
    

---

### 5.5 GAME Screen (Future)

- **● (short press)**
    
    Context-specific (game interaction).
    
- **● (long press)**
    
    Reserved for future use.
    

---

## 6. System-Level Actions (Hidden)

To avoid accidental triggers, system actions require **very long presses**.

### 6.1 BLE Provisioning Reset

- **● (very long press, ~10 seconds)**
    
    Clears Wi-Fi credentials and re-enters BLE provisioning mode.
    

Use cases:

- Changing Wi-Fi network
- Recovering from misconfiguration

This action should provide **clear visual feedback** (e.g., blinking pattern).

---

## 7. User Experience Principles

- No button combinations (e.g., ◀ + ▶)
- No double-clicks
- All destructive or remote actions require long press
- Consistent behavior across screen types
- Predictable and discoverable interactions

---

## 8. Firmware Implementation Notes

Recommended internal handling:

- Button debouncing in firmware
- Distinct timing thresholds:
    - Short press: < 500 ms
    - Long press: ~2–3 s
    - Very long press: ~10 s
- Centralized input handler (FSM-based)
- Button events should not block rendering or networking tasks

---

## 9. Summary

With this 5-button design, TwinGlow achieves:

- Clear navigation
- Fine-grained brightness control
- Safe and intentional content sharing
- Minimal cognitive load
- Clean hardware design

This layout is considered **final and production-ready**.