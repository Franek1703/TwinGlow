import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/services/animation_import/animation_crop.dart';

/// The arithmetic behind the crop view: what the user frames is what every
/// frame gets cropped to.
void main() {
  group('NormalizedCrop', () {
    test('a centred crop takes the largest square a wide canvas allows', () {
      final crop = NormalizedCrop.centered(48, 16);
      final rect = crop.toRect(48, 16);

      expect(rect.size, 16);
      expect(rect.x, 16);
      expect(rect.y, 0);
    });

    test('a centred crop leaves a square canvas whole', () {
      final rect = NormalizedCrop.centered(200, 200).toRect(200, 200);

      expect(rect, (x: 0, y: 0, size: 200));
    });

    test('an oversized selection is clamped to the short side', () {
      final rect = const NormalizedCrop(
        left: 0.9,
        top: 0.9,
        size: 5,
      ).toRect(48, 16);

      expect(rect.size, 16);
      expect(rect.x, 32, reason: 'pulled back inside the canvas');
      expect(rect.y, 0);
    });

    test('rounding never lets the square read past the canvas edge', () {
      final rect = const NormalizedCrop(
        left: 0.999,
        top: 0.999,
        size: 0.5,
      ).toRect(33, 33);

      expect(rect.x + rect.size, lessThanOrEqualTo(33));
      expect(rect.y + rect.size, lessThanOrEqualTo(33));
    });
  });

  group('AnimationCropGeometry', () {
    test('opens on the largest centred square', () {
      final geometry = AnimationCropGeometry.initial(48, 16);

      expect(geometry.zoom, 1);
      expect(geometry.sizePx, 16);
      expect(geometry.crop.toRect(48, 16), (x: 16, y: 0, size: 16));
    });

    test('round-trips through a crop it produced', () {
      final original = AnimationCropGeometry.initial(
        200,
        120,
      ).zoomTo(2, 100, 100, 400).pan(-30, -10, 400);

      final restored = AnimationCropGeometry.fromCrop(original.crop, 200, 120);

      expect(restored.zoom, closeTo(original.zoom, 0.001));
      expect(restored.leftPx, closeTo(original.leftPx, 0.001));
      expect(restored.topPx, closeTo(original.topPx, 0.001));
    });

    test('dragging the artwork moves the window the other way', () {
      final geometry = AnimationCropGeometry.initial(200, 200)
          .zoomTo(2, 0, 0, 400) // 100px window, 4x on screen
          .pan(-40, -40, 400);

      // 40 screen pixels at 4x is 10 source pixels.
      expect(geometry.leftPx, closeTo(10, 0.001));
      expect(geometry.topPx, closeTo(10, 0.001));
    });

    test('panning cannot push the window off the canvas', () {
      final geometry = AnimationCropGeometry.initial(
        200,
        200,
      ).zoomTo(2, 0, 0, 400).pan(-100000, 100000, 400);

      expect(geometry.leftPx, 100, reason: '200 - the 100px window');
      expect(geometry.topPx, 0);
    });

    test('pinching keeps the pixels under the fingers in place', () {
      const viewport = 400.0;
      final before = AnimationCropGeometry.initial(200, 200);
      final anchorBefore = before.leftPx + 300 / before.displayScale(viewport);

      final after = before.zoomTo(2.5, 300, 300, viewport);
      final anchorAfter = after.leftPx + 300 / after.displayScale(viewport);

      expect(after.zoom, 2.5);
      expect(anchorAfter, closeTo(anchorBefore, 0.001));
    });

    test('zoom never goes below the full canvas or past the ceiling', () {
      final geometry = AnimationCropGeometry.initial(200, 200);

      expect(geometry.zoomTo(0.2, 0, 0, 400).zoom, 1);
      expect(
        geometry.zoomTo(1000, 0, 0, 400).zoom,
        AnimationCropGeometry.maxZoom,
      );
    });

    test('the viewport transform lines the window up with its top-left', () {
      const viewport = 320.0;
      final geometry = AnimationCropGeometry.initial(
        200,
        200,
      ).zoomTo(2, 0, 0, viewport);

      // A 100px window shown across 320 logical pixels.
      expect(geometry.displayScale(viewport), closeTo(3.2, 0.001));
      expect(
        geometry.translateX(viewport),
        closeTo(-geometry.leftPx * 3.2, 0.001),
      );
    });
  });
}
