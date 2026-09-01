import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:twin_glow/services/animation_import/animation_crop.dart';
import 'package:twin_glow/services/animation_import/animation_import_converter.dart';
import 'package:twin_glow/services/image_import/editor_image_converter.dart';

import 'support/animation_fixtures.dart';

/// The decode half of animation import: what comes out of a GIF, an animated
/// WebP, and an APNG, and what gets refused before anything is decoded.
void main() {
  const fullCrop = NormalizedCrop(left: 0, top: 0, size: 1);

  List<int> durationsOf(Uint8List bytes) => AnimationImportConverter.convert(
    bytes,
    fullCrop,
  ).pixelArt.frames.map((frame) => frame.durationMs).toList();

  List<int> firstPixelsOf(Uint8List bytes) => AnimationImportConverter.convert(
    bytes,
    fullCrop,
  ).pixelArt.frames.map((frame) => frame.pixels[0][0]).toList();

  group('GIF', () {
    test('extracts every frame in order with its own timing', () {
      final bytes = buildGif(
        width: 16,
        height: 16,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
          [0, 255, 0],
          [0, 0, 255],
        ],
        frames: [
          GifFixtureFrame(
            indices: List.filled(256, 1),
            width: 16,
            height: 16,
            delayCentis: 12,
          ),
          GifFixtureFrame(
            indices: List.filled(256, 2),
            width: 16,
            height: 16,
            delayCentis: 25,
          ),
          GifFixtureFrame(
            indices: List.filled(256, 3),
            width: 16,
            height: 16,
            delayCentis: 8,
          ),
          GifFixtureFrame(
            indices: List.filled(256, 1),
            width: 16,
            height: 16,
            delayCentis: 40,
          ),
        ],
      );

      expect(durationsOf(bytes), [120, 250, 80, 400]);
      expect(firstPixelsOf(bytes), [
        0xFFFF0000,
        0xFF00FF00,
        0xFF0000FF,
        0xFFFF0000,
      ]);
    });

    test('composes a partial frame over the frame it follows', () {
      // The regression this guards: `decodeGif` drops the previous canvas when
      // a partial frame shares the global colour table, which is exactly what
      // an optimised GIF looks like.
      final bytes = buildGif(
        width: 16,
        height: 16,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
          [0, 255, 0],
        ],
        frames: [
          GifFixtureFrame(indices: List.filled(256, 1), width: 16, height: 16),
          GifFixtureFrame(
            indices: const [2, 2, 2, 2],
            x: 2,
            y: 2,
            width: 2,
            height: 2,
            disposal: 1,
          ),
        ],
      );

      final frames = AnimationImportConverter.convert(
        bytes,
        fullCrop,
      ).pixelArt.frames;

      expect(frames, hasLength(2));
      expect(frames[1].pixels[2][2], 0xFF00FF00, reason: 'the patch');
      expect(frames[1].pixels[0][0], 0xFFFF0000, reason: 'kept from frame 1');
      expect(frames[1].pixels[15][15], 0xFFFF0000);
    });

    test('a transparent index leaves the canvas beneath it alone', () {
      final bytes = buildGif(
        width: 16,
        height: 16,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
          [0, 255, 0],
        ],
        frames: [
          GifFixtureFrame(indices: List.filled(256, 1), width: 16, height: 16),
          GifFixtureFrame(
            // Index 0 is declared transparent, so only the corners paint.
            indices: const [2, 0, 0, 2],
            width: 2,
            height: 2,
            disposal: 1,
            transparentIndex: 0,
          ),
        ],
      );

      final frames = AnimationImportConverter.convert(
        bytes,
        fullCrop,
      ).pixelArt.frames;

      expect(frames[1].pixels[0][0], 0xFF00FF00);
      expect(frames[1].pixels[0][1], 0xFFFF0000, reason: 'showed through');
      expect(frames[1].pixels[1][1], 0xFF00FF00);
    });

    test('restore-to-background clears only the disposed rectangle', () {
      final bytes = buildGif(
        width: 16,
        height: 16,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
          [0, 255, 0],
        ],
        frames: [
          GifFixtureFrame(indices: List.filled(256, 1), width: 16, height: 16),
          GifFixtureFrame(
            indices: const [2, 2, 2, 2],
            x: 0,
            y: 0,
            width: 2,
            height: 2,
            disposal: 2,
          ),
          GifFixtureFrame(
            indices: const [2],
            x: 8,
            y: 8,
            width: 1,
            height: 1,
            disposal: 1,
          ),
        ],
      );

      final frames = AnimationImportConverter.convert(
        bytes,
        fullCrop,
      ).pixelArt.frames;

      // Frame 2 disposed its own 2x2 corner to background; the rest of the
      // canvas it inherited from frame 1 is untouched.
      expect(frames[2].pixels[0][0], 0);
      expect(frames[2].pixels[1][1], 0);
      expect(frames[2].pixels[0][2], 0xFFFF0000);
      expect(frames[2].pixels[8][8], 0xFF00FF00);
    });
  });

  group('animated WebP', () {
    test('extracts frames with their own durations', () {
      // The library hands every composed WebP frame frame 0's duration; the
      // timings have to come off the frame table instead.
      final bytes = buildAnimatedWebP(
        frames: [
          solidFrame(16, 255, 0, 0),
          solidFrame(16, 0, 255, 0),
          solidFrame(16, 0, 0, 255),
        ],
        durationsMs: const [80, 900, 1000],
      );

      expect(durationsOf(bytes), [80, 900, 1000]);
      expect(firstPixelsOf(bytes), [0xFFFF0000, 0xFF00FF00, 0xFF0000FF]);
    });
  });

  group('APNG', () {
    test('extracts frames with their own durations', () {
      final bytes = buildApng([
        solidFrame(16, 255, 0, 0, durationMs: 110),
        solidFrame(16, 0, 255, 0, durationMs: 220),
        solidFrame(16, 0, 0, 255, durationMs: 330),
      ]);

      expect(durationsOf(bytes), [110, 220, 330]);
      expect(firstPixelsOf(bytes), [0xFFFF0000, 0xFF00FF00, 0xFF0000FF]);
    });
  });

  group('rejected input', () {
    test('a still PNG is refused rather than padded into an animation', () {
      final bytes = img.encodePng(solidFrame(16, 255, 0, 0));

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(
          isA<ImageImportFailure>().having(
            (e) => e.message,
            'message',
            contains('single frame'),
          ),
        ),
      );
    });

    test('a still GIF is refused', () {
      final bytes = buildGif(
        width: 16,
        height: 16,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
        ],
        frames: [
          GifFixtureFrame(indices: List.filled(256, 1), width: 16, height: 16),
        ],
      );

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(isA<ImageImportFailure>()),
      );
    });

    test('an unsupported format names the formats that work', () {
      final bytes = img.encodeJpg(solidFrame(16, 255, 0, 0));

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(
          isA<ImageImportFailure>().having(
            (e) => e.message,
            'message',
            contains('Unsupported format'),
          ),
        ),
      );
    });

    test('corrupt bytes fail as a message, not a crash', () {
      final bytes = Uint8List.fromList([
        ...'GIF89a'.codeUnits,
        ...List.filled(20, 0),
      ]);

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(isA<ImageImportFailure>()),
      );
    });

    test('an oversized canvas is refused before decoding', () {
      final bytes = _gifHeaderClaiming(width: 8000, height: 8000);

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(
          isA<ImageImportFailure>().having(
            (e) => e.message,
            'message',
            contains('megapixels'),
          ),
        ),
      );
    });

    test('too many frames is refused before decoding', () {
      final bytes = buildGif(
        width: 2,
        height: 2,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
        ],
        frames: List.generate(
          AnimationImportConverter.maxSourceFrames + 1,
          (_) =>
              const GifFixtureFrame(indices: [1, 1, 1, 1], width: 2, height: 2),
        ),
      );

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(
          isA<ImageImportFailure>().having(
            (e) => e.message,
            'message',
            contains('more than ${AnimationImportConverter.maxSourceFrames}'),
          ),
        ),
      );
    });

    test('too much decode work across frames is refused', () {
      // Under the per-frame canvas ceiling, over the total-work one.
      final bytes = buildGif(
        width: 2000,
        height: 2000,
        palette: const [
          [0, 0, 0],
          [255, 0, 0],
        ],
        frames: List.generate(
          10,
          (_) => GifFixtureFrame(indices: const [1], width: 1, height: 1),
        ),
      );

      expect(
        () => AnimationImportConverter.inspectSource(bytes),
        throwsA(
          isA<ImageImportFailure>().having(
            (e) => e.message,
            'message',
            contains('too big to decode'),
          ),
        ),
      );
    });
  });
}

/// A GIF whose logical screen descriptor claims a canvas too big to import.
/// Two 1x1 frames keep it a legal animation, so the size is what fails.
Uint8List _gifHeaderClaiming({required int width, required int height}) {
  return buildGif(
    width: width,
    height: height,
    palette: const [
      [0, 0, 0],
      [255, 0, 0],
    ],
    frames: List.generate(
      2,
      (_) => const GifFixtureFrame(indices: [1], width: 1, height: 1),
    ),
  );
}
