#pragma once
#include <Arduino.h>
#include <vector>
#include "SleepSchedule.h"
// Data structures
struct ScreenConfig {
    String id;
    String type; // CLOCK, IMAGE, ANIMATION, SENSOR
    int order;
    bool enabled;
    bool isShared = false;
    int durationMs;

    // Local IMAGE/ANIMATION asset.
    String assetId;
    // Asset shown first; the pool starts here rather than at index 0.
    String defaultAssetId;
    // Current index into availableAssetIds, advanced by the action button
    int currentAssetIndex;
    std::vector<String> availableAssetIds;
    // When false, the action button does not cycle the pool
    bool allowManualSwitch;

    // Config JSON (for CLOCK/SENSOR) - stored as string for simplicity
    String configJson;
};

// Everything the device reads out of devices/{deviceId}.
//
// Each field carries a sentinel meaning "absent from the document", because a
// field that is missing must never clobber a good cached value - a doc the app
// has not written yet would otherwise reset the timezone to UTC and the
// brightness to zero on the first poll.
struct DeviceDoc {
    int configVersion = 0;
    bool bme680Present = false;
    String tzPosix;              // "" = absent
    int brightness = -1;         // -1 = absent
    bool hasSleep = false;       // false = no sleepMode map in the doc
    SleepSettings sleep;
};

struct AssetData {
    String id;
    String type; // IMAGE, ANIMATION
    String encoding; // SPARSE_I16_RGB888, DELTA_SPARSE_I16_RGB888
    String pixelsJson; // JSON string for pixels
    String basePixelsJson; // JSON string for base pixels (animations)
    String framesJson; // JSON string for frames (animations)
};
