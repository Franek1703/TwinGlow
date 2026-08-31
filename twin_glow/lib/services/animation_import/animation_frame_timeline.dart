import 'dart:math' as math;

import '../../core/codecs/animation_codec.dart';
import '../../core/models/asset_model.dart';
import '../image_import/editor_image_converter.dart';

/// One converted 16x16 grid and how long the source held it.
class TimedGrid {
  final List<List<int>> pixels;
  final int durationMs;

  const TimedGrid({required this.pixels, required this.durationMs});
}

/// The frames an import actually produced, plus what had to give to get there.
class OptimizedTimeline {
  final List<AnimationFrameModel> frames;

  /// Frames the source file held, before any merging or resampling.
  final int sourceFrameCount;

  /// Playback length of [frames]. Diverges from the source when a source
  /// longer than 16x5000ms had to be shortened to fit the editor.
  final int totalDurationMs;

  /// Playback length the source asked for, after per-frame floors but before
  /// the editor's ceilings.
  final int sourceDurationMs;

  const OptimizedTimeline({
    required this.frames,
    required this.sourceFrameCount,
    required this.totalDurationMs,
    required this.sourceDurationMs,
  });

  bool get wasReduced => frames.length < sourceFrameCount;

  bool get wasShortened => totalDurationMs < sourceDurationMs;
}

/// Fits a decoded animation into what the editor and the device accept:
/// 2-16 frames, 50-5000ms each, and a packed payload under
/// [AnimationCodec.maxPackedChars].
///
/// The order of the passes matters. Merging runs before long holds are split
/// into repeats, because doing it the other way round would merge the repeats
/// straight back together. Resampling runs last, over the *unclamped*
/// timeline, so a source's relative timing survives even when its absolute
/// length cannot.
class AnimationFrameTimeline {
  const AnimationFrameTimeline._();

  static OptimizedTimeline build(List<TimedGrid> source) {
    if (source.length < AnimationCodec.minFrames) {
      throw const ImageImportFailure(
        'This file holds a single frame. Choose an animated GIF, WebP, or APNG.',
      );
    }
    if (!source.any(_hasVisiblePixel)) {
      throw const ImageImportFailure(
        'Every frame converted to an empty grid. Crop closer to the artwork '
        'and try again.',
      );
    }

    // A source frame with no timing (or an implausibly fast one) becomes the
    // editor's shortest frame rather than being dropped.
    final floored = source
        .map(
          (grid) => TimedGrid(
            pixels: grid.pixels,
            durationMs: math.max(AnimationCodec.minDurationMs, grid.durationMs),
          ),
        )
        .toList();

    final merged = _mergeIdentical(floored);
    final expanded = _splitLongHolds(merged);
    final sourceDurationMs = _totalDuration(floored);

    for (final candidate in _candidates(expanded)) {
      try {
        AnimationCodec.encode(candidate);
      } on AnimationCodecException {
        continue;
      }
      return OptimizedTimeline(
        frames: candidate,
        sourceFrameCount: source.length,
        totalDurationMs: candidate.fold(0, (sum, f) => sum + f.durationMs),
        sourceDurationMs: sourceDurationMs,
      );
    }

    throw const ImageImportFailure(
      'This animation is too long or changes too much between frames to fit a '
      '16x16 asset. Try a shorter clip or a simpler animation.',
    );
  }

  /// Best fit first, then progressively fewer frames until the payload fits.
  static Iterable<List<AnimationFrameModel>> _candidates(
    List<TimedGrid> timeline,
  ) sync* {
    final direct = timeline.length <= AnimationCodec.maxFrames;
    if (direct) yield _toFrames(timeline);

    final start = math.min(AnimationCodec.maxFrames, timeline.length);
    for (var samples = start; samples >= AnimationCodec.minFrames; samples--) {
      if (direct && samples == timeline.length) continue;
      yield resample(timeline, samples);
    }
  }

  /// Collapses runs of identical grids, keeping their combined screen time.
  ///
  /// Sources routinely repeat a grid once the artwork has been reduced to
  /// 16x16; encoding those repeats spends frame budget on a delta that changes
  /// nothing.
  static List<TimedGrid> _mergeIdentical(List<TimedGrid> source) {
    final merged = <TimedGrid>[];
    for (final grid in source) {
      final previous = merged.isEmpty ? null : merged.last;
      if (previous != null && _sameGrid(previous.pixels, grid.pixels)) {
        merged[merged.length - 1] = TimedGrid(
          pixels: previous.pixels,
          durationMs: previous.durationMs + grid.durationMs,
        );
        continue;
      }
      merged.add(grid);
    }

    // An animation that reduced to one distinct grid still has to be an
    // animation; halving the hold keeps its total length.
    if (merged.length < AnimationCodec.minFrames) {
      final only = merged.single;
      final half = math.max(AnimationCodec.minDurationMs, only.durationMs ~/ 2);
      return [
        TimedGrid(pixels: only.pixels, durationMs: half),
        TimedGrid(pixels: only.pixels, durationMs: only.durationMs - half),
      ];
    }
    return merged;
  }

  /// Splits a hold longer than one frame can express into repeated frames,
  /// but only while the frame budget allows it. Otherwise the hold is left for
  /// the final clamp, which shortens it.
  static List<TimedGrid> _splitLongHolds(List<TimedGrid> source) {
    var needed = 0;
    for (final grid in source) {
      needed +=
          (grid.durationMs + AnimationCodec.maxDurationMs - 1) ~/
          AnimationCodec.maxDurationMs;
    }
    if (needed == source.length) return source;
    if (needed > AnimationCodec.maxFrames) return source;

    final expanded = <TimedGrid>[];
    for (final grid in source) {
      final parts =
          (grid.durationMs + AnimationCodec.maxDurationMs - 1) ~/
          AnimationCodec.maxDurationMs;
      if (parts <= 1) {
        expanded.add(grid);
        continue;
      }
      var remaining = grid.durationMs;
      for (var part = 0; part < parts; part++) {
        final slice = part == parts - 1 ? remaining : grid.durationMs ~/ parts;
        remaining -= slice;
        expanded.add(TimedGrid(pixels: grid.pixels, durationMs: slice));
      }
    }
    return expanded;
  }

  /// Re-times [timeline] onto [samples] equal slices of its own clock.
  ///
  /// Each slice shows whatever the source was showing at its midpoint, so a
  /// grid that occupies most of a slice wins it. Slice boundaries come from
  /// integer division of the running total, which keeps the sum of the sample
  /// durations exactly equal to the source's - before the editor's per-frame
  /// ceiling is applied.
  static List<AnimationFrameModel> resample(
    List<TimedGrid> timeline,
    int samples,
  ) {
    final total = _totalDuration(timeline);
    final frames = <AnimationFrameModel>[];

    for (var i = 0; i < samples; i++) {
      final start = total * i ~/ samples;
      final end = total * (i + 1) ~/ samples;
      final midpoint = (start + end) ~/ 2;
      frames.add(
        AnimationFrameModel(
          pixels: _gridAt(timeline, midpoint),
          durationMs: _clampDuration(end - start),
        ),
      );
    }
    return frames;
  }

  static List<List<int>> _gridAt(List<TimedGrid> timeline, int timeMs) {
    var elapsed = 0;
    for (final grid in timeline) {
      elapsed += grid.durationMs;
      if (timeMs < elapsed) return grid.pixels;
    }
    return timeline.last.pixels;
  }

  static List<AnimationFrameModel> _toFrames(List<TimedGrid> timeline) {
    return timeline
        .map(
          (grid) => AnimationFrameModel(
            pixels: grid.pixels,
            durationMs: _clampDuration(grid.durationMs),
          ),
        )
        .toList();
  }

  static int _clampDuration(int durationMs) => durationMs.clamp(
    AnimationCodec.minDurationMs,
    AnimationCodec.maxDurationMs,
  );

  static int _totalDuration(List<TimedGrid> timeline) =>
      timeline.fold(0, (sum, grid) => sum + grid.durationMs);

  static bool _hasVisiblePixel(TimedGrid grid) =>
      grid.pixels.any((row) => row.any((value) => (value & 0xFFFFFF) != 0));

  static bool _sameGrid(List<List<int>> a, List<List<int>> b) {
    for (var y = 0; y < EditorImageConverter.editorSize; y++) {
      for (var x = 0; x < EditorImageConverter.editorSize; x++) {
        if (a[y][x] != b[y][x]) return false;
      }
    }
    return true;
  }
}
