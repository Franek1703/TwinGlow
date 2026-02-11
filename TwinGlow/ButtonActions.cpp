#include "ButtonActions.h"

ButtonActions::ButtonActions(Buttons* btn, ScreenPlaylist* pl, 
                             MatrixDriver* mat, NvsStore* store, RtdbRepo* db)
    : buttons(btn), playlist(pl), matrix(mat), nvs(store), rtdb(db),
      onFactoryReset(nullptr) {
}

void ButtonActions::update() {
    handleGlobalActions();
    handleContextActions();
}

void ButtonActions::handleGlobalActions() {
    // Previous screen
    if (buttons->getPressType(ButtonId::PREV) == ButtonPressType::SHORT) {
        playlist->previous();
        buttons->clearEvent(ButtonId::PREV);
    }
    
    // Next screen
    if (buttons->getPressType(ButtonId::NEXT) == ButtonPressType::SHORT) {
        playlist->next();
        buttons->clearEvent(ButtonId::NEXT);
    }
    
    // Brightness down
    if (buttons->getPressType(ButtonId::BRIGHT_DOWN) == ButtonPressType::SHORT) {
        handleBrightnessChange(false);
        buttons->clearEvent(ButtonId::BRIGHT_DOWN);
    }
    
    // Brightness up
    if (buttons->getPressType(ButtonId::BRIGHT_UP) == ButtonPressType::SHORT) {
        handleBrightnessChange(true);
        buttons->clearEvent(ButtonId::BRIGHT_UP);
    }
    
    // Factory reset (very long press on ACTION)
    if (buttons->getPressType(ButtonId::ACTION) == ButtonPressType::VERY_LONG) {
        handleFactoryReset();
        buttons->clearEvent(ButtonId::ACTION);
    }
}

void ButtonActions::handleContextActions() {
    ScreenConfig* screen = playlist->getCurrentScreen();
    if (screen == nullptr) return;
    
    ButtonPressType actionPress = buttons->getPressType(ButtonId::ACTION);
    
    if (screen->type == "CLOCK" || screen->type == "SENSOR") {
        // No action for CLOCK/SENSOR
        if (actionPress != ButtonPressType::NONE) {
            buttons->clearEvent(ButtonId::ACTION);
        }
    } else if (screen->type == "IMAGE" || screen->type == "ANIMATION") {
        if (actionPress == ButtonPressType::SHORT) {
            // Switch to next asset
            // TODO: Implement asset switching logic
            Serial.println(F("[ButtonActions] Next asset (not implemented)"));
            buttons->clearEvent(ButtonId::ACTION);
        } else if (actionPress == ButtonPressType::LONG) {
            // Send to pair
            handleSendToPair();
            buttons->clearEvent(ButtonId::ACTION);
        }
    }
}

void ButtonActions::handleBrightnessChange(bool increase) {
    uint8_t current = nvs->getBrightness();
    uint8_t step = 16; // Adjust step size as needed
    
    if (increase) {
        current = min(255, current + step);
    } else {
        current = max(0, (int)current - step);
    }
    
    nvs->setBrightness(current);
    matrix->setBrightness(current);
    
    Serial.print(F("[ButtonActions] Brightness: "));
    Serial.println(current);
}

void ButtonActions::handleSendToPair() {
    ScreenConfig* screen = playlist->getCurrentScreen();
    if (screen == nullptr || screen->pairId.length() == 0) {
        Serial.println(F("[ButtonActions] Cannot send to pair - no pair ID"));
        return;
    }
    
    if (rtdb != nullptr) {
        rtdb->sendToPair(screen->pairId, screen->id, currentAssetId);
        Serial.println(F("[ButtonActions] Sent to pair"));
    }
}

void ButtonActions::handleFactoryReset() {
    Serial.println(F("[ButtonActions] Factory reset triggered!"));
    
    // Visual feedback
    matrix->fill(matrix->color(255, 0, 0)); // Red
    matrix->show();
    delay(500);
    
    // Clear NVS (except deviceId)
    nvs->factoryReset();
    
    // Call callback if set
    if (onFactoryReset != nullptr) {
        onFactoryReset();
    }
    
    // Restart
    ESP.restart();
}
