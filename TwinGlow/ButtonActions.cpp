#include "ButtonActions.h"
#include "CloudWorker.h"
#include "PairingController.h"

ButtonActions::ButtonActions(Buttons* btn, ScreenPlaylist* pl, 
                             MatrixDriver* mat, NvsStore* store, RtdbRepo* db,
                             CloudWorker* worker, PairingController* controller, AssetCache* assets)
    : buttons(btn), playlist(pl), matrix(mat), nvs(store), rtdb(db),
      cloudWorker(worker), pairing(controller), cache(assets), onFactoryReset(nullptr) {
}

void ButtonActions::update() {
    handleGlobalActions();
    handleContextActions();
}

void ButtonActions::handleGlobalActions() {
    // Previous screen
    if (buttons->getPressType(ButtonId::PREV) == ButtonPressType::SHORT) {
        pairing->dismiss();
        playlist->previous();
        buttons->clearEvent(ButtonId::PREV);
    }
    
    // Next screen
    if (buttons->getPressType(ButtonId::NEXT) == ButtonPressType::SHORT) {
        pairing->dismiss();
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
    ButtonPressType overridePress = buttons->getPressType(ButtonId::ACTION);
    if (pairing->hasOverride()) {
        if (overridePress == ButtonPressType::SHORT) {
            pairing->dismiss();
            playlist->resetRotationTimer();
        }
        if (overridePress != ButtonPressType::NONE) buttons->clearEvent(ButtonId::ACTION);
        return;
    }
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
            if (screen->allowManualSwitch && screen->availableAssetIds.size() > 1) {
                screen->currentAssetIndex = (screen->currentAssetIndex + 1) % screen->availableAssetIds.size();
                Serial.print(F("[ButtonActions] Asset "));
                Serial.print(screen->currentAssetIndex + 1);
                Serial.print(F("/"));
                Serial.println(screen->availableAssetIds.size());
            }
            buttons->clearEvent(ButtonId::ACTION);
        } else if (actionPress == ButtonPressType::LONG) {
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

    // Push it up so the app's slider shows what the panel is running at.
    // Queued, not sent: the worker coalesces a held button into one write and
    // owns the retry, so this stays a cheap local call.
    if (cloudWorker != nullptr) {
        cloudWorker->requestBrightnessWrite(current);
    }

    Serial.print(F("[ButtonActions] Brightness: "));
    Serial.println(current);
}

void ButtonActions::handleSendToPair() {
    ScreenConfig* screen = playlist->getCurrentScreen();
    CachedAsset* asset = cache->getAsset(playlist->getCurrentAssetId());
    if (screen && asset && pairing->send(*screen, *asset)) {
        Serial.println(F("[ButtonActions] Current content queued"));
    } else {
        Serial.println(F("[ButtonActions] Send requires an active pair and a cached, shareable image or animation"));
    }
}

void ButtonActions::handleFactoryReset() {
    Serial.println(F("[ButtonActions] Factory reset triggered!"));
    
    // Visual feedback
    matrix->fillStatus(matrix->color(255, 0, 0)); // Red
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
