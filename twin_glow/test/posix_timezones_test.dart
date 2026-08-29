import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/utils/posix_timezones.dart';

void main() {
  group('kIanaToPosixTz', () {
    test('carries the rule the device needs for Poland', () {
      // The bug this table exists to fix: the device showed UTC, two hours
      // behind Poland in summer. M3.5.0/M10.5.0 are the EU changeovers.
      expect(kIanaToPosixTz['Europe/Warsaw'], 'CET-1CEST,M3.5.0,M10.5.0/3');
    });

    test('covers zones with and without DST, and half-hour offsets', () {
      expect(kIanaToPosixTz['America/New_York'], 'EST5EDT,M3.2.0,M11.1.0');
      expect(kIanaToPosixTz['Asia/Tokyo'], 'JST-9');
      expect(kIanaToPosixTz['Asia/Kolkata'], 'IST-5:30');
      expect(kIanaToPosixTz['Australia/Sydney'],
          'AEST-10AEDT,M10.1.0,M4.1.0/3');
    });

    test('is large enough to be the real table, not a stub', () {
      expect(kIanaToPosixTz.length, greaterThan(400));
      expect(kPickableTimeZones.length, greaterThan(400));
    });

    test('every pickable zone resolves to a rule', () {
      for (final zone in kPickableTimeZones) {
        expect(kIanaToPosixTz[zone], isNotNull, reason: '$zone has no rule');
      }
    });

    test('pickable list omits legacy groups but keeps plain UTC', () {
      expect(kPickableTimeZones, contains('UTC'));
      expect(kPickableTimeZones, contains('Europe/Warsaw'));
      expect(kPickableTimeZones.any((z) => z.startsWith('US/')), isFalse);
      expect(kPickableTimeZones.any((z) => z.startsWith('Etc/')), isFalse);
    });
  });

  group('fixedOffsetTz', () {
    test('inverts the sign, because POSIX offsets run the other way', () {
      // Poland in summer is UTC+2, which POSIX writes as UTC-2.
      expect(fixedOffsetTz(const Duration(hours: 2)), 'UTC-2');
      expect(fixedOffsetTz(const Duration(hours: -5)), 'UTC+5');
    });

    test('handles zero and sub-hour offsets', () {
      expect(fixedOffsetTz(Duration.zero), 'UTC0');
      expect(fixedOffsetTz(const Duration(hours: 5, minutes: 30)), 'UTC-5:30');
      expect(fixedOffsetTz(const Duration(hours: -3, minutes: -30)),
          'UTC+3:30');
    });
  });

  group('posixTzFor', () {
    test('prefers the table over the offset', () {
      expect(posixTzFor('Europe/Warsaw', const Duration(hours: 9)),
          'CET-1CEST,M3.5.0,M10.5.0/3');
    });

    test('falls back to a fixed offset for an unknown zone', () {
      expect(posixTzFor('Mars/Olympus_Mons', const Duration(hours: 2)),
          'UTC-2');
    });
  });
}
