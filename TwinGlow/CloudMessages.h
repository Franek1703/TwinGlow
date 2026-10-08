#pragma once
#include "FirestoreModels.h"
#include "PairSnapshot.h"
enum class CloudOperation : uint8_t {
    PRESENCE = 0,
    TELEMETRY = 1,
    CONFIG_CHECK = 2,
    REVISION_CHECK = 3,
    PAIR_EVENT = 4,
    ASSET_FETCH = 5,
    BRIGHTNESS_WRITE = 6,
    PAIR_STATE = 7,
    PAIR_FETCH = 8,
    PAIR_ACK = 9,
    SCREENS_FETCH = 10,
    COUNT = 11
};

// Queue payloads contain only trivially copyable data. DeviceDoc owns Arduino
// Strings, so successful config reads cross the queue as a heap pointer and
// are deleted by the main loop after processing.
struct CloudResult {
    CloudOperation operation;
    bool attempted;
    bool success;
    int errorCode;
    DeviceDoc* deviceDoc;
    AssetData* assetData;
    int revision;
    PairState* pairState;
    PairSnapshot* pairSnapshot;
    PairSend* pairSend;
    PairMeta* pairMeta;
    bool displayed;
    std::vector<ScreenConfig>* screens;
    // Value actually written by BRIGHTNESS_WRITE, so the main loop can tell
    // whether the panel moved again while the write was in flight.
    int brightness;
    char resourceId[96];
};
