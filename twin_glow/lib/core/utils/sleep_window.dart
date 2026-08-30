/// Sleep-window arithmetic, kept in one place so the app and the firmware agree.
///
/// The device runs the same three rules in `TwinGlow/SleepSchedule.cpp`; the
/// test suite covers the same cases on both sides.
library;

/// Whether [nowMinute] falls inside the window `[startMinute, endMinute)`.
///
/// All values are minutes since local midnight. A window whose end is before
/// its start crosses midnight - 23:00 to 07:00 is the expected shape.
/// A zero-length window never matches, so a half-configured schedule cannot
/// leave the panel dimmed around the clock.
bool isWithinSleepWindow(int startMinute, int endMinute, int nowMinute) {
  if (startMinute == endMinute) return false;
  if (startMinute < endMinute) {
    return nowMinute >= startMinute && nowMinute < endMinute;
  }
  return nowMinute >= startMinute || nowMinute < endMinute;
}

/// `1380` -> `23:00`, for display.
String formatMinuteOfDay(int minuteOfDay) {
  final normalized = minuteOfDay % (24 * 60);
  final hours = (normalized ~/ 60).toString().padLeft(2, '0');
  final minutes = (normalized % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}
