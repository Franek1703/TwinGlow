#include "PairingController.h"
#include "PlaylistUpdate.h"
#include "ScreenPlaylist.h"
#include "FirestorePagination.h"
#include <cassert>
#include <fstream>
#include <sstream>
#include <iostream>
#include <map>
#include <time.h>
unsigned long fakeMillis=10000;
uint32_t painted[256];unsigned shows=0;
MatrixDriver::MatrixDriver():currentBrightness(128){}
MatrixDriver::~MatrixDriver()=default;
void MatrixDriver::fill(uint32_t color){std::fill(painted,painted+256,color);}
void MatrixDriver::show(){++shows;}
uint32_t MatrixDriver::color(uint32_t v){return v;}
uint32_t MatrixDriver::color(uint8_t r,uint8_t g,uint8_t b){return (r<<16)|(g<<8)|b;}
void MatrixDriver::setPixelOriented(uint8_t x,uint8_t y,uint32_t color){painted[y*16+x]=color;}
std::map<std::string,uint64_t> handled;uint64_t sequence=0;bool failNvs=false;
NvsStore::NvsStore():initialized(true){}
NvsStore::~NvsStore()=default;
uint64_t NvsStore::reserveSendSequence(){return ++sequence;}
uint64_t NvsStore::getHandledSequence(const String& id){return handled[id.c_str()];}
bool NvsStore::setHandledSequence(const String& id,uint64_t n){if(failNvs)return false;handled[id.c_str()]=n;return true;}
struct Transport:PairTransport{
    PairSend* sent=nullptr;PairMeta* fetched=nullptr;PairMeta* ack=nullptr;bool displayed=false;unsigned fetches=0;
    bool isStarted()const override{return true;}
    bool requestPairState()override{return true;}
    bool requestPairSend(PairSend* s)override{if(sent)return false;sent=s;return true;}
    bool requestPairFetch(PairMeta* m)override{if(fetched)return false;fetched=m;++fetches;return true;}
    bool requestPairAck(PairMeta* m,bool d)override{if(ack)return false;ack=m;displayed=d;return true;}
    ~Transport(){delete sent;delete fetched;delete ack;}
};
String fixture(const char* name){std::ifstream file(std::string("tests/fixtures/")+name);std::stringstream stream;stream<<file.rdbuf();return String(stream.str());}
PairMeta meta(uint64_t seq=1){PairMeta m;m.pairId="pair";m.senderDeviceId="A";m.recipientDeviceId="B";m.screenId="screen";m.assetId="asset";m.eventId=String(std::to_string(seq));m.sequence=seq;m.sentAt=uint64_t(time(nullptr))*1000;return m;}
void state(PairingController& c,PairMeta m){PairState p;p.pairId="pair";p.partnerDeviceId="A";p.incoming=m;CloudResult r{};r.operation=CloudOperation::PAIR_STATE;r.success=true;r.pairState=&p;c.process(r);}
void deliver(PairingController& c,Transport& t,const String& content,bool success=true){
    assert(t.fetched);PairSnapshot s;s.meta=*t.fetched;AssetCache parser;s.invalid=!parser.parseAssetObject("event",[&](){static JsonDocument d;deserializeJson(d,content);return d.as<JsonObject>();}(),s.asset);
    delete t.fetched;t.fetched=nullptr;
    CloudResult r{};r.operation=CloudOperation::PAIR_FETCH;r.success=success;r.pairSnapshot=new PairSnapshot(std::move(s));c.process(r);delete r.pairSnapshot;
}
ScreenConfig screen(const char* id,const char* asset){ScreenConfig s{};s.id=id;s.type="IMAGE";s.enabled=true;s.isShared=true;s.assetId=asset;s.defaultAssetId=asset;s.availableAssetIds={asset};return s;}
int main(){
    // Empty/new devices and a final nonempty page both omit nextPageToken.
    // Neither may enqueue a request for the literal token "null".
    for (const char* response : {"{}", "{\"documents\":[]}",
            "{\"documents\":[{\"name\":\"screen\"}]}",
            "{\"nextPageToken\":null}", "{\"nextPageToken\":\"\"}"}) {
        JsonDocument page; assert(!deserializeJson(page,response));
        String token="previous-page";
        assert(readFirestorePageToken(page["nextPageToken"],token));
        assert(token.isEmpty());
    }
    for (const char* tokenValue : {"second-page", "null"}) {
        JsonDocument page;page["nextPageToken"]=tokenValue;
        String token;
        assert(readFirestorePageToken(page["nextPageToken"],token));
        assert(token==tokenValue); // Tokens are opaque; a literal string is valid.
    }
    for (const char* response : {"{\"nextPageToken\":17}",
            "{\"nextPageToken\":true}", "{\"nextPageToken\":{}}",
            "{\"nextPageToken\":[]}"}) {
        JsonDocument page;assert(!deserializeJson(page,response));
        String token="previous-page";
        assert(!readFirestorePageToken(page["nextPageToken"],token));
        assert(token=="previous-page");
    }
    AssetCache parser;CachedAsset image,animation;
    assert(parser.parseAsset("image",fixture("pairing-image.json"),image));
    assert(parser.parseAsset("animation",fixture("pairing-animation.json"),animation));
    String encoded;assert(encodePairContent(image,encoded));JsonDocument d;deserializeJson(d,encoded);assert(d["pixelsPacked"]=="00ff00001100ff00");
    assert(encodePairContent(animation,encoded));deserializeJson(d,encoded);assert(d["frameDeltasPacked"][0]=="000000001100ff00");
    PairSend publication;publication.meta=meta();publication.contentJson=encoded;
    String payload;assert(encodePairPublication(publication,payload));JsonDocument root;assert(!deserializeJson(root,payload));
    assert(root["config/B/incoming"]["sentAt"][".sv"]=="timestamp");
    const char* tmp=getenv("TMPDIR");std::ofstream(std::string(tmp?tmp:"/tmp")+"/twinglow-firmware-publication.json")<<payload.c_str();
    CachedAsset legacy;assert(parser.parseAsset("legacy","{\"type\":\"animation\",\"encoding\":\"SPARSE_PACKED_V1\",\"pixelsPacked\":\"00ff0000\"}",legacy)&&legacy.type=="IMAGE");
    PairSnapshot decoded;JsonDocument envelope;writePairMeta(envelope["meta"].to<JsonObject>(),meta(),false);envelope["content"].set(d.as<JsonObject>());String raw;serializeJson(envelope,raw);assert(decodePairSnapshot(raw,decoded)&&!decoded.invalid);
    assert(!decodePairSnapshot("{",decoded));
    MatrixDriver matrix;RenderAsset render(&matrix);render.renderAnimation(&animation,0);assert(painted[0]==0xff0000);fakeMillis+=100;render.renderAnimation(&animation,0);assert(painted[0]==0 && painted[17]==0x00ff00);fakeMillis+=250;render.renderAnimation(&animation,0);assert(painted[0]==0xff0000);
    NvsStore nvs;Transport t;PairingController c(&nvs,&t,&render);c.begin("B");state(c,meta());c.tick(true);assert(t.fetches==0);c.tick(false);deliver(c,t,fixture("pairing-image.json"));assert(c.hasOverride() && !t.ack);unsigned before=shows;c.render();assert(shows==before+1 && painted[17]==0x00ff00);c.tick(false);assert(t.ack&&t.displayed);delete t.ack;t.ack=nullptr;c.dismiss();fakeMillis+=6000;c.tick(false);assert(t.fetches==1);
    Transport rebootTransport;PairingController reboot(&nvs,&rebootTransport,&render);reboot.begin("B");state(reboot,meta());reboot.tick(false);assert(!reboot.hasOverride()&&rebootTransport.fetches==0);
    state(c,meta(2));c.tick(false);deliver(c,t,fixture("pairing-animation.json"),false);assert(!c.hasOverride()&&nvs.getHandledSequence("pair")==1);fakeMillis+=6000;c.tick(false);deliver(c,t,fixture("pairing-animation.json"));assert(c.hasOverride());c.render();assert(painted[0]==0xff0000);
    state(c,meta(3));fakeMillis+=6000;c.tick(false);deliver(c,t,fixture("pairing-image.json"),false);assert(c.hasOverride()&&nvs.getHandledSequence("pair")==2&&painted[0]==0xff0000);fakeMillis+=6000;c.tick(false);failNvs=true;deliver(c,t,fixture("pairing-image.json"));failNvs=false;assert(c.hasOverride()&&nvs.getHandledSequence("pair")==2);
    fakeMillis+=6000;c.tick(false);deliver(c,t,"{\"type\":\"IMAGE\",\"encoding\":\"wrong\"}");assert(c.hasOverride()&&nvs.getHandledSequence("pair")==3);
    state(c,meta(4));fakeMillis+=6000;c.tick(false);state(c,meta(5));deliver(c,t,fixture("pairing-image.json"));assert(nvs.getHandledSequence("pair")==3);
    fakeMillis+=6000;c.tick(false);deliver(c,t,fixture("pairing-image.json"));assert(nvs.getHandledSequence("pair")==5);
    PairState empty;CloudResult unpair{};unpair.operation=CloudOperation::PAIR_STATE;unpair.success=true;unpair.pairState=&empty;c.process(unpair);assert(!c.hasOverride());
    auto expired=meta(6);expired.sentAt-=PAIR_EVENT_MAX_AGE_MS+1000;state(c,expired);c.tick(false);assert(nvs.getHandledSequence("pair")==6);
    // Capture is immutable, pending is replaced, CLOCK and unshared content cannot send.
    Transport sender;PairingController a(&nvs,&sender,&render);a.begin("A");PairState ps;ps.pairId="pair";ps.partnerDeviceId="B";CloudResult sr{};sr.operation=CloudOperation::PAIR_STATE;sr.success=true;sr.pairState=&ps;a.process(sr);
    auto local=screen("screen","image");assert(a.send(local,image));image.pixels[0].color=0x0000ff;assert(a.send(local,image));a.tick(false);assert(sender.sent);deserializeJson(d,sender.sent->contentJson);assert(d["pixelsPacked"]=="000000ff1100ff00");local.isShared=false;assert(!a.send(local,image));local.isShared=true;local.type="CLOCK";assert(!a.send(local,image));
    CloudResult transient{};transient.operation=CloudOperation::PAIR_EVENT;transient.pairSend=sender.sent;sender.sent=nullptr;transient.success=false;transient.errorCode=503;a.process(transient);
    a.tick(false);assert(!sender.sent);fakeMillis+=5000;a.tick(false);assert(sender.sent);
    transient.pairSend=sender.sent;sender.sent=nullptr;a.process(transient);fakeMillis+=PAIR_SEND_TTL_MS+1;a.tick(false);assert(!sender.sent);
    Transport reverseTransport;PairingController reverse(&nvs,&reverseTransport,&render);reverse.begin("A");PairState reverseState;reverseState.pairId="reverse";reverseState.partnerDeviceId="B";reverseState.incoming=meta();reverseState.incoming.pairId="reverse";reverseState.incoming.senderDeviceId="B";reverseState.incoming.recipientDeviceId="A";
    CloudResult reverseResult{};reverseResult.operation=CloudOperation::PAIR_STATE;reverseResult.success=true;reverseResult.pairState=&reverseState;reverse.process(reverseResult);reverse.tick(false);deliver(reverse,reverseTransport,fixture("pairing-animation.json"));assert(reverse.hasOverride());reverse.render();assert(painted[0]==0xff0000);
    // Failure during staging cannot replace live objects or consume a config revision.
    AssetCache live;live.addAsset(image);auto original=live.getAsset("image");PlaylistUpdate update({screen("one","image"),screen("two","new")},live,9);assert(update.accept("image",fixture("pairing-image.json")));assert(!update.accept("new","{"));assert(live.getAsset("image")==original&&live.getAsset("image")->pixels[0].color==0x0000ff);
    assert(update.accept("new",fixture("pairing-image.json"))&&update.ready());
    ScreenPlaylist playlist;auto one=screen("one","image"),two=screen("two","new");two.availableAssetIds={"new","image"};playlist.setScreens({one,two});playlist.next();playlist.getCurrentScreen()->currentAssetIndex=1;playlist.setScreens({two,one});assert(playlist.getCurrentScreen()->id=="two"&&playlist.getCurrentAssetId()=="image");
    std::cout<<"Native pairing tests passed: codec, rendering, sleep, ack, duplicates, restart, failures, latest send, expiry, unpair, cache, selection\n";
}
