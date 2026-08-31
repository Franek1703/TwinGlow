import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:twin_glow/services/animation_import/animation_crop.dart';
import 'package:twin_glow/services/animation_import/animation_import_converter.dart';
import 'package:twin_glow/services/image_import/editor_image_converter.dart';

import 'support/animation_fixtures.dart';

/// Crop and pixel reduction: what every frame is cropped to, and how those
/// crops become 16x16 grids.
void main() {
  const fullCrop = NormalizedCrop(left: 0, top: 0, size: 1);

  test('scaled-up pixel art reconstructs without smoothing', () {
    // Each 16x16 source cell is one editor pixel; a checkerboard survives only
    // if the reduction never blends neighbouring cells.
    final frames = [
      _checkerboard(size: 256, cell: 16, even: 0xFF00D9FF, odd: 0xFFFF006E),
      _checkerboard(size: 256, cell: 16, even: 0xFFFF006E, odd: 0xFF00D9FF),
    ];
    final bytes = buildApng(frames);

    final result = AnimationImportConverter.convert(bytes, fullCrop);
    final first = result.pixelArt.frames.first.pixels;

    expect(result.suggestedMode, ImageConversionMode.pixelArt);
    expect(first[0][0], 0xFF00D9FF);
    expect(first[0][1], 0xFFFF006E);
    expect(first[1][0], 0xFFFF006E);
    expect(result.pixelArt.frames[1].pixels[0][0], 0xFFFF006E);
  });

  test('every converted frame is exactly 16x16', () {
    final bytes = buildApng([
      _gradientFrame(137, offset: 0),
      _gradientFrame(137, offset: 40),
      _gradientFrame(137, offset: 80),
    ]);

    final result = AnimationImportConverter.convert(bytes, fullCrop);

    for (final timeline in [result.pixelArt, result.photo]) {
      for (final frame in timeline.frames) {
        expect(frame.pixels, hasLength(16));
        expect(frame.pixels.every((row) => row.length == 16), isTrue);
      }
    }
    expect(result.suggestedMode, ImageConversionMode.photo);
  });

  test('transparent source pixels become the editor off pixel', () {
    final opaque = solidFrame(16, 255, 0, 0);
    final clear = img.Image(width: 16, height: 16, numChannels: 4);
    img.fill(clear, color: img.ColorRgba8(255, 0, 0, 0));
    clear.frameDuration = 100;

    final result = AnimationImportConverter.convert(
      buildApng([opaque, clear]),
      fullCrop,
    );

    expect(result.pixelArt.frames[0].pixels[0][0], 0xFFFF0000);
    expect(result.pixelArt.frames[1].pixels[0][0], 0);
  });

  test('one crop applies identically to every frame of a wide source', () {
    // 48x16: the left third is the only part any crop below selects, and each
    // frame paints a different colour there.
    final frames = [
      _thirdsFrame(left: 0xFFFF0000),
      _thirdsFrame(left: 0xFF00FF00),
      _thirdsFrame(left: 0xFF0000FF),
    ];

    final result = AnimationImportConverter.convert(
      buildApng(frames),
      const NormalizedCrop(left: 0, top: 0, size: 16 / 48),
    );

    expect(result.cropSize, 16);
    expect(result.pixelArt.frames.map((frame) => frame.pixels[8][8]).toList(), [
      0xFFFF0000,
      0xFF00FF00,
      0xFF0000FF,
    ]);
    // The middle and right thirds are never in view, in any frame.
    for (final frame in result.pixelArt.frames) {
      expect(frame.pixels.expand((row) => row).toSet(), hasLength(1));
    }
  });

  test('a non-square crop rectangle is never produced', () {
    final result = AnimationImportConverter.convert(
      buildApng([
        _thirdsFrame(left: 0xFFFF0000),
        _thirdsFrame(left: 0xFF00FF00),
      ]),
      const NormalizedCrop(left: 0.5, top: 0, size: 0.9),
    );

    // 0.9 * 48 = 43.2px wide, but the canvas is only 16px tall, so the square
    // is clamped to the short side and pulled back inside the canvas.
    expect(result.cropSize, 16);
  });

  test('switching modes selects the matching precomputed result', () {
    final bytes = buildApng([
      _gradientFrame(64, offset: 0),
      _gradientFrame(64, offset: 60),
    ]);

    final result = AnimationImportConverter.convert(bytes, fullCrop);

    expect(
      result.framesFor(ImageConversionMode.pixelArt),
      same(result.pixelArt.frames),
    );
    expect(
      result.framesFor(ImageConversionMode.photo),
      same(result.photo.frames),
    );
    expect(
      result.framesFor(ImageConversionMode.pixelArt).first.pixels,
      isNot(result.framesFor(ImageConversionMode.photo).first.pixels),
    );
  });

  test('one photographic frame is enough to suggest Photo', () {
    final bytes = buildApng([
      _checkerboard(size: 256, cell: 16, even: 0xFF00D9FF, odd: 0xFFFF006E),
      _gradientFrame(256, offset: 0),
    ]);

    expect(
      AnimationImportConverter.convert(bytes, fullCrop).suggestedMode,
      ImageConversionMode.photo,
    );
  });

  test('the crop-view still is bounded and reports the real canvas', () {
    final bytes = buildApng([
      _gradientFrame(1024, offset: 0),
      _gradientFrame(1024, offset: 30),
    ]);

    final preview = AnimationImportConverter.loadPreview(bytes);
    final decoded = img.decodePng(preview.previewPng)!;

    expect(preview.sourceWidth, 1024);
    expect(preview.sourceHeight, 1024);
    expect(preview.sourceFrameCount, 2);
    expect(decoded.width, AnimationImportConverter.previewMaxEdge);
    expect(decoded.height, AnimationImportConverter.previewMaxEdge);
  });
}

img.Image _checkerboard({
  required int size,
  required int cell,
  required int even,
  required int odd,
}) {
  final frame = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final color = ((x ~/ cell) + (y ~/ cell)).isEven ? even : odd;
      frame.setPixelRgba(
        x,
        y,
        (color >> 16) & 0xFF,
        (color >> 8) & 0xFF,
        color & 0xFF,
        255,
      );
    }
  }
  frame.frameDuration = 100;
  return frame;
}

img.Image _gradientFrame(int size, {required int offset}) {
  final frame = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      frame.setPixelRgba(
        x,
        y,
        (x * 255 ~/ (size - 1) + offset) % 256,
        (y * 255 ~/ (size - 1) + offset) % 256,
        (x + y) % 256,
        255,
      );
    }
  }
  frame.frameDuration = 100;
  return frame;
}

/// 48x16, painted in three flat 16-wide columns.
img.Image _thirdsFrame({required int left}) {
  final frame = img.Image(width: 48, height: 16, numChannels: 4);
  const middle = 0xFF111111;
  const right = 0xFF222222;
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 48; x++) {
      final color = x < 16 ? left : (x < 32 ? middle : right);
      frame.setPixelRgba(
        x,
        y,
        (color >> 16) & 0xFF,
        (color >> 8) & 0xFF,
        color & 0xFF,
        255,
      );
    }
  }
  frame.frameDuration = 100;
  return frame;
}
