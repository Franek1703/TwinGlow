#include "PairSnapshot.h"
namespace {
bool identifier(const String& s){
    if(s.length()==0 || s.length()>95)return false;
    for(size_t i=0;i<s.length();++i)if(s[i]=='.'||s[i]=='#'||s[i]=='$'||s[i]=='['||s[i]==']'||s[i]=='/')return false;
    return true;
}
String packedPixels(const std::vector<Pixel>& pixels){
    String out;if(!out.reserve(pixels.size()*8))return String();
    for(const auto& p:pixels){char run[9];snprintf(run,sizeof(run),"%02x%06lx",(unsigned)p.index,(unsigned long)(p.color&0xffffff));out+=run;}
    return out;
}
}
bool PairMeta::valid()const{return identifier(eventId)&&identifier(pairId)&&identifier(senderDeviceId)&&identifier(recipientDeviceId)&&identifier(screenId)&&identifier(assetId)&&senderDeviceId!=recipientDeviceId&&sequence>0&&sequence<=9007199254740991ULL;}
bool readPairMeta(JsonObjectConst o,PairMeta& m){
    if(o["schemaVersion"]!=1 || !o["sequence"].is<uint64_t>() || !o["sentAt"].is<uint64_t>())return false;
    const char* names[]={"eventId","pairId","senderDeviceId","recipientDeviceId","screenId","assetId"};
    for(const auto* name:names)if(!o[name].is<const char*>())return false;
    m.eventId=o["eventId"].as<String>();m.pairId=o["pairId"].as<String>();m.senderDeviceId=o["senderDeviceId"].as<String>();
    m.recipientDeviceId=o["recipientDeviceId"].as<String>();m.screenId=o["screenId"].as<String>();m.assetId=o["assetId"].as<String>();
    m.sequence=o["sequence"].as<uint64_t>();m.sentAt=o["sentAt"].as<uint64_t>();return m.valid()&&m.sentAt>0;
}
void writePairMeta(JsonObject o,const PairMeta& m,bool serverTime){
    o["schemaVersion"]=1;o["eventId"]=m.eventId;o["pairId"]=m.pairId;o["senderDeviceId"]=m.senderDeviceId;o["recipientDeviceId"]=m.recipientDeviceId;
    o["screenId"]=m.screenId;o["assetId"]=m.assetId;o["sequence"]=m.sequence;
    if(serverTime)o["sentAt"][".sv"]="timestamp";else o["sentAt"]=m.sentAt;
}
bool encodePairContent(const CachedAsset& a,String& result){
    JsonDocument doc;size_t chars=0;
    if(a.isAnimation()){
        if(a.frames.size()<ANIM_MIN_FRAMES||a.frames.size()>ANIM_MAX_FRAMES)return false;
        doc["type"]="ANIMATION";doc["encoding"]="DELTA_SPARSE_PACKED_V1";doc["frameCount"]=a.frames.size();doc["loop"]=true;
        auto durations=doc["frameDurationsMs"].to<JsonArray>();auto deltas=doc["frameDeltasPacked"].to<JsonArray>();
        for(size_t i=0;i<a.frames.size();++i){const auto& f=a.frames[i];
            if(f.durationMs<50||f.durationMs>5000||f.delta.size()>256)return false;
            String packed=packedPixels(f.delta);if(packed.length()!=f.delta.size()*8)return false;chars+=packed.length();
            if(i==0)doc["basePixelsPacked"]=packed;else deltas.add(packed);
            durations.add(f.durationMs);
        }
        if(chars>8192)return false;
    }else{
        if(a.type!="IMAGE"||a.pixels.size()>256)return false;
        String packed=packedPixels(a.pixels);if(packed.length()!=a.pixels.size()*8)return false;
        doc["type"]="IMAGE";doc["encoding"]="SPARSE_PACKED_V1";doc["pixelsPacked"]=packed;
    }
    if(doc.overflowed())return false;
    result="";size_t expected=measureJson(doc);return serializeJson(doc,result)==expected && result.length()==expected;
}
bool decodePairSnapshot(const String& json,PairSnapshot& result){
    if(json.length()>PAIR_MAX_JSON_BYTES)return false;
    JsonDocument doc;if(deserializeJson(doc,json))return false;
    if(!readPairMeta(doc["meta"].as<JsonObjectConst>(),result.meta))return false;
    JsonObject content=doc["content"].as<JsonObject>();
    String encoding=content["encoding"].as<String>();
    if((encoding!="SPARSE_PACKED_V1"&&encoding!="DELTA_SPARSE_PACKED_V1")||doc.overflowed()){result.invalid=true;return true;}
    AssetCache parser;result.invalid=!parser.parseAssetObject(result.meta.eventId,content,result.asset);return true;
}

bool encodePairPublication(const PairSend& send,String& result){
    if(!send.meta.valid()||send.contentJson.isEmpty())return false;
    JsonDocument doc;writePairMeta(doc.to<JsonObject>(),send.meta,true);
    String meta;if(serializeJson(doc,meta)!=measureJson(doc)||doc.overflowed())return false;
    doc.clear();doc["mailbox"]="pairing/mailboxes/"+send.meta.pairId+"/"+send.meta.senderDeviceId;
    doc["incoming"]="config/"+send.meta.recipientDeviceId+"/incoming";
    String mailbox,incoming;serializeJson(doc["mailbox"],mailbox);serializeJson(doc["incoming"],incoming);
    size_t expected=mailbox.length()+incoming.length()+2*meta.length()+send.contentJson.length()+25;
    if(expected>PAIR_MAX_JSON_BYTES||!result.reserve(expected))return false;
    result="{";result+=mailbox;result+=":{\"meta\":";result+=meta;result+=",\"content\":";
    result+=send.contentJson;result+="},";result+=incoming;result+=":";result+=meta;result+="}";
    return result.length()==expected;
}
