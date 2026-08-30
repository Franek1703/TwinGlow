import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/utils/brightness_scale.dart';

void main() {
  group('percentToRaw', () {
    test('maps the ends of the range exactly', () {
      expect(percentToRaw(0), 0);
      expect(percentToRaw(100), 255);
    });

    test('maps the midpoint', () {
      expect(percentToRaw(50), 128);
    });

    test('clamps out-of-range input rather than overflowing 0-255', () {
      expect(percentToRaw(-10), 0);
      expect(percentToRaw(150), 255);
    });
  });

  group('rawToPercent', () {
    test('maps the ends of the range exactly', () {
      expect(rawToPercent(0), 0);
      expect(rawToPercent(255), 100);
    });

    test('clamps values outside the byte range', () {
      expect(rawToPercent(-5), 0);
      expect(rawToPercent(999), 100);
    });
  });

  test('a percent survives a round trip through the stored value', () {
    // The slider must land back where the owner left it after a reload.
    for (final percent in [5, 20, 40, 60, 80, 100]) {
      expect(
        rawToPercent(percentToRaw(percent.toDouble())).round(),
        percent,
        reason: '$percent% did not round-trip',
      );
    }
  });

  test('the day floor is above zero so the panel cannot be lost', () {
    // MatrixDriver clamps 0 up to 1, which is invisible - only sleep mode is
    // allowed to blank the display.
    expect(kMinBrightnessPercent, greaterThan(0));
    expect(percentToRaw(kMinBrightnessPercent), greaterThan(0));
  });
}
