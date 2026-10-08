#include "PlaylistUpdate.h"
#include <algorithm>
PlaylistUpdate::PlaylistUpdate(std::vector<ScreenConfig> nextScreens,const AssetCache& live,int revision)
    :screens(std::move(nextScreens)),cache(live),version(revision){
    std::vector<String> images;
    auto add=[](std::vector<String>& ids,const String& id){
        if(!id.isEmpty() && std::find(ids.begin(),ids.end(),id)==ids.end())ids.push_back(id);
    };
    for(auto& s:screens){
        if(!s.enabled)continue;
        s.type.toUpperCase();s.currentAssetIndex=0;
        if(!s.defaultAssetId.isEmpty())s.assetId=s.defaultAssetId;
        else if(s.assetId.isEmpty()&&!s.availableAssetIds.empty())s.assetId=s.availableAssetIds[0];
        for(size_t i=0;i<s.availableAssetIds.size();++i)if(s.availableAssetIds[i]==s.assetId)s.currentAssetIndex=i;
        if(s.type=="IMAGE"||s.type=="ANIMATION"){
            auto& ids=s.type=="ANIMATION"?required:images;
            add(ids,s.assetId);for(const auto& id:s.availableAssetIds)add(ids,id);
        }
    }
    for(const auto& id:images)add(required,id);
}
bool PlaylistUpdate::accept(const String& id,const String& json){
    if(ready()||id!=next())return false;
    CachedAsset asset;
    if(!cache.parseAsset(id,json,asset))return false;
    return accept(id, std::move(asset));
}
bool PlaylistUpdate::accept(const String& id, CachedAsset&& asset) {
    if (ready() || id != next() || asset.id != id || !asset.isValid()) return false;
    cache.addAsset(std::move(asset)); ++index; return true;
}
bool PlaylistUpdate::acceptUnchanged(const String& id) {
    if (ready() || id != next()) return false;
    auto asset = cache.getAsset(id);
    if (!asset || asset->sourceRevision.isEmpty()) return false;
    ++index; return true;
}
