#include "SleepSchedule.h"

bool isWithinSleepWindow(int startMinute, int endMinute, int nowMinute) {
    if (startMinute == endMinute) return false;
    if (startMinute < endMinute) {
        return nowMinute >= startMinute && nowMinute < endMinute;
    }
    return nowMinute >= startMinute || nowMinute < endMinute;
}
