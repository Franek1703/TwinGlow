import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/utils/sleep_window.dart';

/// These cases mirror `TwinGlow/SleepSchedule.cpp` one for one. If the rules
/// change, both sides move together.
void main() {
  group('isWithinSleepWindow - same-day window (13:00-15:00)', () {
    const start = 13 * 60;
    const end = 15 * 60;

    test('includes the start minute', () {
      expect(isWithinSleepWindow(start, end, start), isTrue);
    });

    test('excludes the end minute, so the window is half-open', () {
      expect(isWithinSleepWindow(start, end, end), isFalse);
    });

    test('matches inside and misses outside', () {
      expect(isWithinSleepWindow(start, end, 14 * 60), isTrue);
      expect(isWithinSleepWindow(start, end, 12 * 60 + 59), isFalse);
      expect(isWithinSleepWindow(start, end, 16 * 60), isFalse);
    });
  });

  group('isWithinSleepWindow - crossing midnight (23:00-07:00)', () {
    const start = 23 * 60;
    const end = 7 * 60;

    test('matches late evening', () {
      expect(isWithinSleepWindow(start, end, 23 * 60), isTrue);
      expect(isWithinSleepWindow(start, end, 23 * 60 + 59), isTrue);
    });

    test('matches after midnight', () {
      expect(isWithinSleepWindow(start, end, 0), isTrue);
      expect(isWithinSleepWindow(start, end, 6 * 60 + 59), isTrue);
    });

    test('stops at the end minute', () {
      expect(isWithinSleepWindow(start, end, 7 * 60), isFalse);
    });

    test('misses the middle of the day', () {
      expect(isWithinSleepWindow(start, end, 12 * 60), isFalse);
      expect(isWithinSleepWindow(start, end, 22 * 60 + 59), isFalse);
    });
  });

  test('a zero-length window never matches', () {
    // Otherwise a half-configured schedule would dim the panel around the clock.
    for (final minute in [0, 60, 720, 1439]) {
      expect(isWithinSleepWindow(600, 600, minute), isFalse);
    }
  });

  group('formatMinuteOfDay', () {
    test('pads to a 24-hour clock', () {
      expect(formatMinuteOfDay(0), '00:00');
      expect(formatMinuteOfDay(7 * 60), '07:00');
      expect(formatMinuteOfDay(23 * 60), '23:00');
      expect(formatMinuteOfDay(13 * 60 + 5), '13:05');
    });

    test('wraps a value past midnight', () {
      expect(formatMinuteOfDay(24 * 60), '00:00');
    });
  });
}
