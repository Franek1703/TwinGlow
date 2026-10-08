#pragma once
#include "CloudMessages.h"
#include "PairTransport.h"
#include "NvsStore.h"
#include "RenderAsset.h"
#include <memory>

class PairingController {
public:
    PairingController(NvsStore* nvs,PairTransport* worker,RenderAsset* renderer);
    void begin(const String& deviceId);
    void tick(bool blanked);
    void process(CloudResult& result);
    bool send(const ScreenConfig& screen,const CachedAsset& asset);
    bool render();
    bool hasOverride()const{return bool(active);}
    void dismiss();
private:
    NvsStore* nvs;PairTransport* worker;RenderAsset* renderer;
    String deviceId;
    PairState state;
    std::unique_ptr<PairSnapshot> active;
    std::unique_ptr<PairSend> pending;
    std::unique_ptr<PairMeta> ack;
    bool ackDisplayed=false,sendBusy=false,fetchBusy=false,ackBusy=false,blanked=false,needsDisplayAck=false;
    uint32_t lastPoll=0,retryAt=0,sendRetryAt=0,ackRetryAt=0;
    void reject(const PairMeta& meta);
    bool current(const PairMeta& meta)const;
};
