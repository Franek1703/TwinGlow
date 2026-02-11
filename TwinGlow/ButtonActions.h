#ifndef BUTTON_ACTIONS_H
#define BUTTON_ACTIONS_H

#include "Buttons.h"
#include "ScreenPlaylist.h"
#include "MatrixDriver.h"
#include "NvsStore.h"
#include "RtdbRepo.h"

/**
 * Button action handler
 * Maps button events to device actions
 */
class ButtonActions {
public:
    ButtonActions(Buttons* buttons, ScreenPlaylist* playlist, 
                  MatrixDriver* matrix, NvsStore* nvs, RtdbRepo* rtdb);
    
    void update(); // Call in loop() to handle button events
    
    // Factory reset callback
    void (*onFactoryReset)();
    
private:
    Buttons* buttons;
    ScreenPlaylist* playlist;
    MatrixDriver* matrix;
    NvsStore* nvs;
    RtdbRepo* rtdb;
    
    String currentPairId;
    String currentScreenId;
    String currentAssetId;
    
    void handleGlobalActions();
    void handleContextActions();
    void handleBrightnessChange(bool increase);
    void handleSendToPair();
    void handleFactoryReset();
};

#endif // BUTTON_ACTIONS_H
