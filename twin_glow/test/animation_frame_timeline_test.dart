import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/codecs/animation_codec.dart';
import 'package:twin_glow/services/animation_import/animation_frame_timeline.dart';
import 'package:twin_glow/services/image_import/editor_image_converter.dart';

/// Fitting a source animation into 2-16 frames of 50-5000ms that still packs
/// under the codec's payload ceiling.
void main() {
  test('durations already inside the editor range are kept exactly', () {
    final timeline = AnimationFrameTimeline.build([
      _grid(0xFFFF0000, 120),
      _grid(0xFF00FF00, 250),
      _grid(0xFF0000FF, 3000),
    ]);

    expect(timeline.frames.map((frame) => frame.durationMs).toList(), [
      120,
      250,
      3000,
    ]);
    expect(timeline.totalDurationMs, 3370);
    expect(timeline.wasReduced, isFalse);
    expect(timeline.wasShortened, isFalse);
  });

  test('zero and sub-50ms durations become the shortest editor frame', () {
    final timeline = AnimationFrameTimeline.build([
      _grid(0xFFFF0000, 0),
      _grid(0xFF00FF00, 10),
      _grid(0xFF0000FF, 49),
      _grid(0xFFFFFF00, 50),
    ]);

    expect(timeline.frames.map((frame) => frame.durationMs).toList(), [
      50,
      50,
      50,
      50,
    ]);
  });

  test('identical consecutive frames merge without changing total time', () {
    final timeline = AnimationFrameTimeline.build([
      _grid(0xFFFF0000, 100),
      _grid(0xFFFF0000, 100),
      _grid(0xFFFF0000, 100),
      _grid(0xFF00FF00, 200),
    ]);

    expect(timeline.frames, hasLength(2));
    expect(timeline.frames.map((frame) => frame.durationMs).toList(), [
      300,
      200,
    ]);
    expect(timeline.totalDurationMs, 500);
    expect(timeline.sourceFrameCount, 4);
    expect(timeline.wasReduced, isTrue);
    expect(timeline.wasShortened, isFalse);
  });

  test('an animation that reduces to one grid still gets two frames', () {
    final timeline = AnimationFrameTimeline.build([
      _grid(0xFFFF0000, 300),
      _grid(0xFFFF0000, 300),
    ]);

    expect(timeline.frames, hasLength(AnimationCodec.minFrames));
    expect(timeline.totalDurationMs, 600);
  });

  test(
    'a hold longer than one frame splits into repeats while budget allows',
    () {
      final timeline = AnimationFrameTimeline.build([
        _grid(0xFFFF0000, 12000),
        _grid(0xFF00FF00, 200),
      ]);

      expect(timeline.frames, hasLength(4));
      expect(timeline.frames.map((frame) => frame.durationMs).toList(), [
        4000,
        4000,
        4000,
        200,
      ]);
      expect(timeline.totalDurationMs, 12200);
      expect(timeline.wasShortened, isFalse);
    },
  );

  test('more than 16 frames resample to a codec-valid sequence', () {
    final source = List.generate(
      40,
      (index) => _grid(0xFF000000 | (index * 6) << 8, 100),
    );

    final timeline = AnimationFrameTimeline.build(source);

    expect(timeline.frames.length, lessThanOrEqualTo(AnimationCodec.maxFrames));
    expect(
      timeline.frames.length,
      greaterThanOrEqualTo(AnimationCodec.minFrames),
    );
    expect(timeline.totalDurationMs, 4000, reason: 'source total preserved');
    expect(timeline.sourceFrameCount, 40);
    expect(timeline.wasReduced, isTrue);
    expect(() => AnimationCodec.encode(timeline.frames), returnsNormally);
  });

  test('resampling picks the grid holding each slice midpoint', () {
    // 17 frames forces a resample; the first grid occupies 90% of the clock,
    // so almost every slice should land on it.
    final source = [
      _grid(0xFFFF0000, 9000),
      for (var i = 0; i < 16; i++) _grid(0xFF000000 | (i + 1), 62),
    ];

    final timeline = AnimationFrameTimeline.build(source);
    final reds = timeline.frames
        .where((frame) => frame.pixels[0][0] == 0xFFFF0000)
        .length;

    expect(timeline.frames, hasLength(AnimationCodec.maxFrames));
    expect(reds, greaterThanOrEqualTo(14));
  });

  test('a source longer than 16 frames can play is shortened, not refused', () {
    // Frames that differ in a single pixel, so the payload budget stays out of
    // the way and the 16x5000ms playback ceiling is what actually binds.
    final source = List.generate(20, (index) => _sparse(index, 20000));

    final timeline = AnimationFrameTimeline.build(source);

    expect(timeline.frames, hasLength(AnimationCodec.maxFrames));
    expect(
      timeline.frames.every(
        (frame) => frame.durationMs == AnimationCodec.maxDurationMs,
      ),
      isTrue,
    );
    expect(timeline.totalDurationMs, 80000);
    expect(timeline.wasShortened, isTrue);
    expect(() => AnimationCodec.encode(timeline.frames), returnsNormally);
  });

  test('a dense animation is reduced until the packed payload fits', () {
    // Every frame repaints all 256 pixels in a colour no other frame uses, so
    // every delta is maximal and only a handful of frames can survive.
    final source = List.generate(30, (index) => _noise(index, 100));

    final timeline = AnimationFrameTimeline.build(source);
    final encoded = AnimationCodec.encode(timeline.frames);

    expect(
      encoded.packedLength,
      lessThanOrEqualTo(AnimationCodec.maxPackedChars),
    );
    expect(timeline.frames.length, lessThan(AnimationCodec.maxFrames));
    expect(timeline.wasReduced, isTrue);
  });

  test('a source with no lit pixel is a recoverable failure', () {
    expect(
      () => AnimationFrameTimeline.build([_grid(0, 100), _grid(0, 100)]),
      throwsA(
        isA<ImageImportFailure>().having(
          (e) => e.message,
          'message',
          contains('empty grid'),
        ),
      ),
    );
  });

  test('a single source frame is a recoverable failure', () {
    expect(
      () => AnimationFrameTimeline.build([_grid(0xFFFF0000, 100)]),
      throwsA(isA<ImageImportFailure>()),
    );
  });
}

TimedGrid _grid(int color, int durationMs) {
  return TimedGrid(
    pixels: List.generate(16, (_) => List.filled(16, color)),
    durationMs: durationMs,
  );
}

/// A frame that differs from its neighbours by one pixel, so its delta is
/// nearly free.
TimedGrid _sparse(int seed, int durationMs) {
  final pixels = List.generate(16, (_) => List.filled(16, 0xFF102030));
  pixels[seed % 16][(seed * 7) % 16] = 0xFF000000 | (seed + 1);
  return TimedGrid(pixels: pixels, durationMs: durationMs);
}

/// A frame whose every pixel is unique to [seed], so deltas never compress.
TimedGrid _noise(int seed, int durationMs) {
  return TimedGrid(
    pixels: List.generate(
      16,
      (y) => List.generate(
        16,
        (x) => 0xFF000000 | ((seed * 4099 + y * 251 + x * 17) & 0xFFFFFF) | 1,
      ),
    ),
    durationMs: durationMs,
  );
}
