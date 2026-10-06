#ifndef SCREEN_PLAYLIST_H
#define SCREEN_PLAYLIST_H

#include <Arduino.h>
#include <vector>
#include "FirestoreModels.h"

/**
 * Screen playlist manager
 * Handles screen rotation and navigation
 */
class ScreenPlaylist {
public:
    ScreenPlaylist();
    
    // Load screens
    void setScreens(const std::vector<ScreenConfig>& screens);
    
    // Navigation
    void next();
    void previous();
    void setCurrentIndex(int index);
    
    // Current screen
    ScreenConfig* getCurrentScreen();
    const ScreenConfig* getCurrentScreen() const;
    int getCurrentIndex() const { return currentIndex; }
    
    // Current asset id for IMAGE/ANIMATION (from assetId or availableAssetIds[currentAssetIndex])
    String getCurrentAssetId() const;
    
    // Rotation
    bool shouldRotate(); // Check if duration elapsed
    void resetRotationTimer();
    
    // Status
    bool isEmpty() const { return screens.empty(); }
    size_t size() const { return screens.size(); }
    
private:
    std::vector<ScreenConfig> screens;
    int currentIndex;
    unsigned long screenStartMs;
};

#endif // SCREEN_PLAYLIST_H
