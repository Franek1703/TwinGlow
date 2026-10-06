#pragma once
#include "PairingConfig.h"
#include "AssetCache.h"
#include <ArduinoJson.h>

struct PairMeta {
    String eventId,pairId,senderDeviceId,recipientDeviceId,screenId,assetId;
    uint64_t sequence=0,sentAt=0;
    bool valid() const;
};
struct PairState {
    String pairId,partnerDeviceId;
    int revision=-1;
    PairMeta incoming;
};
struct PairSnapshot {
    PairMeta meta;
    CachedAsset asset;
    bool invalid=false;
};
struct PairSend {
    PairMeta meta;
    String contentJson;
    uint32_t queuedAt=0;
};
bool readPairMeta(JsonObjectConst object,PairMeta& meta);
void writePairMeta(JsonObject object,const PairMeta& meta,bool serverTime);
bool encodePairContent(const CachedAsset& asset,String& result);
bool decodePairSnapshot(const String& json,PairSnapshot& result);

bool encodePairPublication(const PairSend& send,String& result);
