#ifndef BUTTONS_H
#define BUTTONS_H

#include <Arduino.h>
#include "Config.h"

/**
 * Button press types
 */
enum class ButtonPressType {
    NONE,
    SHORT,
    LONG,
    VERY_LONG
};

/**
 * Button IDs
 */
enum class ButtonId {
    PREV,
    NEXT,
    BRIGHT_DOWN,
    BRIGHT_UP,
    ACTION
};

/**
 * Button state
 */
struct ButtonState {
    ButtonId id;
    ButtonPressType pressType;
    bool isPressed;
    unsigned long pressStartMs;
    unsigned long lastChangeMs;
};

/**
 * Button handler with debouncing and press detection
 */
class Buttons {
public:
    Buttons();
    
    void begin();
    void update(); // Call in loop()
    
    // Get button events
    ButtonPressType getPressType(ButtonId button) const;
    bool isPressed(ButtonId button) const;
    
    // Clear events (call after handling)
    void clearEvent(ButtonId button);
    
private:
    ButtonState buttons[5];
    
    uint8_t getPin(ButtonId button) const;
    void updateButton(ButtonId button);
    ButtonPressType detectPressType(ButtonState& state);
};

#endif // BUTTONS_H
