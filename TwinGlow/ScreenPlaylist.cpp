#include "ScreenPlaylist.h"

ScreenPlaylist::ScreenPlaylist() : currentIndex(0), screenStartMs(0) {
}

void ScreenPlaylist::retainAuthorizedSharedScreens(const std::vector<ScreenConfig>& next) {
    std::vector<ScreenConfig> allowed;
    for(const auto& screen:screens) {
        bool keep=screen.sharedScreenId.isEmpty();
        for(const auto& candidate:next)if(candidate.sharedScreenId==screen.sharedScreenId && !screen.sharedScreenId.isEmpty())keep=true;
        if(keep)allowed.push_back(screen);
    }
    if(allowed.size()!=screens.size())setScreens(allowed);
}

void ScreenPlaylist::removeSharedScreens() {
    std::vector<ScreenConfig> local;
    for(const auto& screen:screens)if(screen.sharedScreenId.isEmpty())local.push_back(screen);
    if(local.size()!=screens.size())setScreens(local);
}

void ScreenPlaylist::setScreens(const std::vector<ScreenConfig>& newScreens) {
    String selectedId=getCurrentScreen()?getCurrentScreen()->id:String();
    std::vector<ScreenConfig> nextScreens;
    for(auto screen:newScreens){
        if(!screen.enabled)continue;
        for(const auto& old:screens)if(old.id==screen.id){
            String oldAsset=old.assetId;
            if(old.currentAssetIndex>=0 && (size_t)old.currentAssetIndex<old.availableAssetIds.size())oldAsset=old.availableAssetIds[old.currentAssetIndex];
            for(size_t a=0;a<screen.availableAssetIds.size();++a)if(screen.availableAssetIds[a]==oldAsset)screen.currentAssetIndex=a;
        }
        nextScreens.push_back(std::move(screen));
    }
    screens=std::move(nextScreens);currentIndex=0;
    for(size_t i=0;i<screens.size();++i)if(screens[i].id==selectedId){currentIndex=i;break;}
    screenStartMs=millis();

    Serial.print(F("[Playlist] Loaded "));
    Serial.print(screens.size());
    Serial.print(F(" of "));
    Serial.print(newScreens.size());
    Serial.println(F(" screens (disabled ones filtered out)"));
}

void ScreenPlaylist::next() {
    if (screens.empty()) return;
    
    currentIndex = (currentIndex + 1) % screens.size();
    screenStartMs = millis();
    
    Serial.print(F("[Playlist] Next screen: "));
    Serial.println(currentIndex);
}

void ScreenPlaylist::previous() {
    if (screens.empty()) return;
    
    currentIndex = (currentIndex - 1 + screens.size()) % screens.size();
    screenStartMs = millis();
    
    Serial.print(F("[Playlist] Previous screen: "));
    Serial.println(currentIndex);
}

void ScreenPlaylist::setCurrentIndex(int index) {
    if (index >= 0 && index < screens.size()) {
        currentIndex = index;
        screenStartMs = millis();
    }
}

ScreenConfig* ScreenPlaylist::getCurrentScreen() {
    if (screens.empty() || currentIndex < 0 || (size_t)currentIndex >= screens.size()) {
        return nullptr;
    }
    return &screens[currentIndex];
}

const ScreenConfig* ScreenPlaylist::getCurrentScreen() const {
    if (screens.empty() || currentIndex < 0 || (size_t)currentIndex >= screens.size()) {
        return nullptr;
    }
    return &screens[currentIndex];
}

String ScreenPlaylist::getCurrentAssetId() const {
    const ScreenConfig* s = getCurrentScreen();
    if (s == nullptr) return "";
    if (!s->availableAssetIds.empty() && s->currentAssetIndex >= 0 && s->currentAssetIndex < (int)s->availableAssetIds.size()) {
        return s->availableAssetIds[s->currentAssetIndex];
    }
    return s->assetId;
}

bool ScreenPlaylist::shouldRotate() {
    // Nothing to rotate to.
    if (screens.size() < 2) return false;

    ScreenConfig* screen = getCurrentScreen();
    if (screen == nullptr) return false;

    // durationMs <= 0 means "hold this screen", not "advance immediately".
    if (screen->durationMs <= 0) return false;

    unsigned long elapsed = millis() - screenStartMs;
    return elapsed >= (unsigned long)screen->durationMs;
}

void ScreenPlaylist::resetRotationTimer() {
    screenStartMs = millis();
}
