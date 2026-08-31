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
 *
 * firedType is the strongest event already reported for the hold in progress.
 * A held button crosses its threshold on every 10 ms pass through update(), so
 * without this the press type was re-armed continuously and a single 3-second
 * hold delivered hundreds of LONG events. It is reset when the button goes down
 * and gates both the while-held checks and the type detected on release.
 */
struct ButtonState {
    ButtonId id;
    ButtonPressType pressType;
    bool isPressed;
    unsigned long pressStartMs;
    unsigned long lastChangeMs;
    ButtonPressType firedType;
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
