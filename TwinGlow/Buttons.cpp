#include "Buttons.h"

Buttons::Buttons() {
    buttons[0] = {ButtonId::PREV, ButtonPressType::NONE, false, 0, 0};
    buttons[1] = {ButtonId::NEXT, ButtonPressType::NONE, false, 0, 0};
    buttons[2] = {ButtonId::BRIGHT_DOWN, ButtonPressType::NONE, false, 0, 0};
    buttons[3] = {ButtonId::BRIGHT_UP, ButtonPressType::NONE, false, 0, 0};
    buttons[4] = {ButtonId::ACTION, ButtonPressType::NONE, false, 0, 0};
}

void Buttons::begin() {
    pinMode(BUTTON_PREV_PIN, INPUT_PULLUP);
    pinMode(BUTTON_NEXT_PIN, INPUT_PULLUP);
    pinMode(BUTTON_BRIGHT_DOWN_PIN, INPUT_PULLUP);
    pinMode(BUTTON_BRIGHT_UP_PIN, INPUT_PULLUP);
    pinMode(BUTTON_ACTION_PIN, INPUT_PULLUP);
    
    Serial.println("[Buttons] Initialized");
}

void Buttons::update() {
    updateButton(ButtonId::PREV);
    updateButton(ButtonId::NEXT);
    updateButton(ButtonId::BRIGHT_DOWN);
    updateButton(ButtonId::BRIGHT_UP);
    updateButton(ButtonId::ACTION);
}

uint8_t Buttons::getPin(ButtonId button) const {
    switch (button) {
        case ButtonId::PREV: return BUTTON_PREV_PIN;
        case ButtonId::NEXT: return BUTTON_NEXT_PIN;
        case ButtonId::BRIGHT_DOWN: return BUTTON_BRIGHT_DOWN_PIN;
        case ButtonId::BRIGHT_UP: return BUTTON_BRIGHT_UP_PIN;
        case ButtonId::ACTION: return BUTTON_ACTION_PIN;
        default: return 0;
    }
}

void Buttons::updateButton(ButtonId button) {
    int index = (int)button;
    if (index < 0 || index >= 5) return;
    
    ButtonState& state = buttons[index];
    uint8_t pin = getPin(button);
    bool currentState = !digitalRead(pin); // Inverted because of pull-up
    
    unsigned long now = millis();
    
    // Debounce
    if (currentState != state.isPressed) {
        if (now - state.lastChangeMs < BUTTON_DEBOUNCE_MS) {
            return; // Still debouncing
        }
        state.lastChangeMs = now;
    }
    
    // State changed
    if (currentState != state.isPressed) {
        state.isPressed = currentState;
        
        if (state.isPressed) {
            // Button pressed
            state.pressStartMs = now;
            state.pressType = ButtonPressType::NONE;
        } else {
            // Button released - detect press type
            state.pressType = detectPressType(state);
        }
    } else if (state.isPressed) {
        // Button still pressed - check for long/very long
        unsigned long pressDuration = now - state.pressStartMs;
        
        if (pressDuration >= BUTTON_VERY_LONG_PRESS_MS) {
            state.pressType = ButtonPressType::VERY_LONG;
        } else if (pressDuration >= BUTTON_LONG_PRESS_MS) {
            state.pressType = ButtonPressType::LONG;
        }
    }
}

ButtonPressType Buttons::detectPressType(ButtonState& state) {
    if (!state.isPressed) {
        unsigned long pressDuration = millis() - state.pressStartMs;
        
        if (pressDuration >= BUTTON_VERY_LONG_PRESS_MS) {
            return ButtonPressType::VERY_LONG;
        } else if (pressDuration >= BUTTON_LONG_PRESS_MS) {
            return ButtonPressType::LONG;
        } else if (pressDuration > 0) {
            return ButtonPressType::SHORT;
        }
    }
    
    return ButtonPressType::NONE;
}

ButtonPressType Buttons::getPressType(ButtonId button) const {
    int index = (int)button;
    if (index < 0 || index >= 5) return ButtonPressType::NONE;
    return buttons[index].pressType;
}

bool Buttons::isPressed(ButtonId button) const {
    int index = (int)button;
    if (index < 0 || index >= 5) return false;
    return buttons[index].isPressed;
}

void Buttons::clearEvent(ButtonId button) {
    int index = (int)button;
    if (index >= 0 && index < 5) {
        buttons[index].pressType = ButtonPressType::NONE;
    }
}
