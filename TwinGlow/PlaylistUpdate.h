#pragma once
#include "AssetCache.h"
#include "FirestoreModels.h"
// A staged cache shares unchanged objects with the live cache. Replacements
// remain private until every referenced download has parsed successfully.
class PlaylistUpdate {
public:
    PlaylistUpdate(std::vector<ScreenConfig> screens,const AssetCache& live,int version);
    std::vector<ScreenConfig> screens;
    AssetCache cache;
    std::vector<String> required;
    int version;
    String sharingPairId;
    int sharingVersion=0;
    bool sharingActive=false;
    size_t index=0;
    bool ready()const{return index==required.size();}
    String next()const{return ready()?String():required[index];}
    bool accept(const String& id,const String& json);
    bool accept(const String& id, CachedAsset&& asset);
    bool acceptUnchanged(const String& id);
};
