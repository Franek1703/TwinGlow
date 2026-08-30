#ifndef SLEEP_SCHEDULE_H
#define SLEEP_SCHEDULE_H

#include <Arduino.h>

/**
 * Nightly dim window, as set from the app.
 *
 * Times are minutes since local midnight so the device never has to parse a
 * clock string. The app writes the same representation; see
 * twin_glow/lib/core/utils/sleep_window.dart, which implements the identical
 * three rules.
 */
struct SleepSettings {
    bool enabled = false;
    int startMinute = 0;
    int endMinute = 0;
    // 0-255 while asleep. 0 means blank the panel outright - brightness alone
    // cannot express that, because MatrixDriver clamps 0 up to 1.
    uint8_t brightness = 0;
};

// True when nowMinute falls inside [startMinute, endMinute).
// An end before the start crosses midnight, which is the usual case (23:00-07:00).
// A zero-length window never matches, so a half-configured schedule cannot
// leave the panel dimmed around the clock.
bool isWithinSleepWindow(int startMinute, int endMinute, int nowMinute);

#endif // SLEEP_SCHEDULE_H
