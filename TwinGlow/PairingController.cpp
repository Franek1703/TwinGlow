#include "PairingController.h"

#include <esp_system.h>
#include <time.h>
namespace {
bool transientFailure(int code){return code<=0 || code==408 || code==429 || code>=500;}
}
PairingController::PairingController(NvsStore* n,PairTransport* w,RenderAsset* r):nvs(n),worker(w),renderer(r){}
void PairingController::begin(const String& id){deviceId=id;}
bool PairingController::current(const PairMeta& m)const{
    return m.valid() && m.pairId==state.pairId && m.senderDeviceId==state.partnerDeviceId && m.recipientDeviceId==deviceId;
}
void PairingController::tick(bool dark){
    blanked=dark;
    if(!worker->isStarted())return;
    if(lastPoll==0||millis()-lastPoll>=PAIR_POLL_MS){if(worker->requestPairState())lastPoll=millis();}
    if(pending && (pending->meta.pairId!=state.pairId||millis()-pending->queuedAt>=PAIR_SEND_TTL_MS)){
        Serial.println(F("[Pairing] Pending send expired or pairing changed"));pending.reset();
    }
    if(pending&&!sendBusy&&(int32_t)(millis()-sendRetryAt)>=0){if(worker->requestPairSend(pending.get())){pending.release();sendBusy=true;}}
    if(ack&&!ackBusy&&(int32_t)(millis()-ackRetryAt)>=0){if(worker->requestPairAck(ack.get(),ackDisplayed)){ack.release();ackBusy=true;}}
    if(blanked||fetchBusy||!current(state.incoming)||time(nullptr)<1000000000||(int32_t)(millis()-retryAt)<0)return;
    if(state.incoming.sequence<=nvs->getHandledSequence(state.pairId))return;
    uint64_t now=uint64_t(time(nullptr))*1000;
    if(state.incoming.sentAt>now+60000)return;
    if(now>state.incoming.sentAt && now-state.incoming.sentAt>PAIR_EVENT_MAX_AGE_MS){reject(state.incoming);return;}
    auto m=std::unique_ptr<PairMeta>(new(std::nothrow)PairMeta(state.incoming));
    if(m&&worker->requestPairFetch(m.get())){m.release();fetchBusy=true;}
}
void PairingController::process(CloudResult& r){
    if(r.operation==CloudOperation::PAIR_STATE && r.success && r.pairState){
        bool changed=state.pairId!=r.pairState->pairId||state.partnerDeviceId!=r.pairState->partnerDeviceId;
        state=*r.pairState;
        if(changed){dismiss();pending.reset();ack.reset();retryAt=0;}
    }
    if(r.operation==CloudOperation::PAIR_EVENT){
        sendBusy=false;std::unique_ptr<PairSend> sent(r.pairSend);r.pairSend=nullptr;
        if(!r.success && sent && !pending && sent->meta.pairId==state.pairId && millis()-sent->queuedAt<PAIR_SEND_TTL_MS && transientFailure(r.errorCode)){pending=std::move(sent);sendRetryAt=millis()+5000;}
        Serial.println(r.success?F("[Pairing] Snapshot published"):F("[Pairing] Snapshot send failed; transient failures retry"));
    }
    if(r.operation==CloudOperation::PAIR_FETCH){
        fetchBusy=false;retryAt=millis()+5000;
        if(r.success && r.pairSnapshot){auto& s=*r.pairSnapshot;
            if(!current(s.meta) || s.meta.eventId!=state.incoming.eventId || s.meta.sequence!=state.incoming.sequence)return;
            if(s.meta.sequence<=nvs->getHandledSequence(s.meta.pairId))return;
            uint64_t now=uint64_t(time(nullptr))*1000;
            if(now>s.meta.sentAt && now-s.meta.sentAt>PAIR_EVENT_MAX_AGE_MS){reject(s.meta);return;}
            if(s.invalid){reject(s.meta);return;}
            if(blanked)return;
            // NVS failure leaves the working display untouched.
            if(!nvs->setHandledSequence(s.meta.pairId,s.meta.sequence))return;
            active.reset(r.pairSnapshot);r.pairSnapshot=nullptr;needsDisplayAck=true;renderer->resetAnimation();
        }
    }
    if(r.operation==CloudOperation::PAIR_ACK){
        ackBusy=false;std::unique_ptr<PairMeta> attempted(r.pairMeta);r.pairMeta=nullptr;
        if(!r.success && attempted && !ack && current(*attempted) && attempted->eventId==state.incoming.eventId && transientFailure(r.errorCode)){ack=std::move(attempted);ackDisplayed=r.displayed;ackRetryAt=millis()+5000;}
    }
}
bool PairingController::send(const ScreenConfig& screen,const CachedAsset& asset){
    if(blanked||hasOverride()||!screen.isShared||(screen.type!="IMAGE"&&screen.type!="ANIMATION")||state.pairId.isEmpty())return false;
    auto next=std::unique_ptr<PairSend>(new(std::nothrow)PairSend());if(!next)return false;
    if(!encodePairContent(asset,next->contentJson))return false;
    next->meta.pairId=state.pairId;next->meta.senderDeviceId=deviceId;next->meta.recipientDeviceId=state.partnerDeviceId;
    next->meta.screenId=screen.id;next->meta.assetId=asset.id;next->meta.sequence=nvs->reserveSendSequence();
    char id[33];snprintf(id,sizeof(id),"%08lx%08lx%08lx%08lx",(unsigned long)esp_random(),(unsigned long)esp_random(),(unsigned long)esp_random(),(unsigned long)esp_random());
    next->meta.eventId=id;if(!next->meta.valid())return false;next->queuedAt=millis();pending=std::move(next);sendRetryAt=0;
    Serial.println(F("[Pairing] Selected content captured; latest pending send wins"));return true;
}
void PairingController::reject(const PairMeta& m){
    if(!nvs->setHandledSequence(m.pairId,m.sequence))return;
    ack.reset(new(std::nothrow)PairMeta(m));ackDisplayed=false;
}
bool PairingController::render(){
    if(!active)return false;
    if(active->asset.isAnimation())renderer->renderAnimation(&active->asset,0);else renderer->renderImage(&active->asset,0);
    if(needsDisplayAck){ack.reset(new(std::nothrow)PairMeta(active->meta));ackDisplayed=true;needsDisplayAck=false;}
    return true;
}
void PairingController::dismiss(){active.reset();needsDisplayAck=false;renderer->resetAnimation();}
