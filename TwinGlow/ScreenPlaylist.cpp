#include "ScreenPlaylist.h"

ScreenPlaylist::ScreenPlaylist() : currentIndex(0), screenStartMs(0) {
}

void ScreenPlaylist::setScreens(const std::vector<ScreenConfig>& newScreens) {
    screens = newScreens;
    currentIndex = 0;
    screenStartMs = millis();
    
    Serial.print("[Playlist] Loaded ");
    Serial.print(screens.size());
    Serial.println(" screens");
}

void ScreenPlaylist::next() {
    if (screens.empty()) return;
    
    currentIndex = (currentIndex + 1) % screens.size();
    screenStartMs = millis();
    
    Serial.print("[Playlist] Next screen: ");
    Serial.println(currentIndex);
}

void ScreenPlaylist::previous() {
    if (screens.empty()) return;
    
    currentIndex = (currentIndex - 1 + screens.size()) % screens.size();
    screenStartMs = millis();
    
    Serial.print("[Playlist] Previous screen: ");
    Serial.println(currentIndex);
}

void ScreenPlaylist::setCurrentIndex(int index) {
    if (index >= 0 && index < screens.size()) {
        currentIndex = index;
        screenStartMs = millis();
    }
}

ScreenConfig* ScreenPlaylist::getCurrentScreen() {
    if (screens.empty() || currentIndex < 0 || currentIndex >= screens.size()) {
        return nullptr;
    }
    return &screens[currentIndex];
}

bool ScreenPlaylist::shouldRotate() {
    if (screens.empty()) return false;
    
    ScreenConfig* screen = getCurrentScreen();
    if (screen == nullptr) return false;
    
    unsigned long elapsed = millis() - screenStartMs;
    return elapsed >= screen->durationMs;
}

void ScreenPlaylist::resetRotationTimer() {
    screenStartMs = millis();
}
