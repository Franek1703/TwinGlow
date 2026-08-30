import '../models/asset_model.dart';

/// Thrown when an animation cannot be represented in DELTA_SPARSE_PACKED_V1.
///
/// Oversized or malformed animations are rejected rather than truncated: a
/// silently clipped animation reaches the device as a valid-looking asset that
/// plays the wrong thing, which is far harder to diagnose than a save error.
class AnimationCodecException implements Exception {
  final String message;
  const AnimationCodecException(this.message);

  @override
  String toString() => message;
}

/// Firestore payload for one animation asset.
class EncodedAnimation {
  final String basePixelsPacked;
  final List<String> frameDeltasPacked;
  final List<int> frameDurationsMs;

  const EncodedAnimation({
    required this.basePixelsPacked,
    required this.frameDeltasPacked,
    required this.frameDurationsMs,
  });

  int get frameCount => frameDurationsMs.length;

  /// Total packed characters billed against [AnimationCodec.maxPackedChars].
  int get packedLength =>
      basePixelsPacked.length +
      frameDeltasPacked.fold<int>(0, (sum, delta) => sum + delta.length);
}

/// Encodes and decodes 16x16 frame animations.
///
/// Wire format `DELTA_SPARSE_PACKED_V1` reuses the `IIRRGGBB` grouping that
/// images already use for `SPARSE_PACKED_V1`, so the device parses both with
/// the same primitive:
///
/// * `basePixelsPacked` - every lit pixel of frame 0.
/// * `frameDeltasPacked[i]` - the change from frame `i` to frame `i + 1`.
///   A group whose colour is `000000` clears that pixel.
/// * `frameDurationsMs[i]` - how long frame `i` stays visible.
///
/// Deltas are cumulative: frame `n` is the base with deltas 0..n-1 applied in
/// order. Encoding transitions rather than whole frames is what keeps a
/// 16-frame animation inside the device's JSON buffer.
class AnimationCodec {
  const AnimationCodec._();

  static const String encodingName = 'DELTA_SPARSE_PACKED_V1';
  static const String legacyEncodingName = 'DELTA_SPARSE_I16_RGB888';

  static const int minFrames = 2;
  static const int maxFrames = 16;
  static const int minDurationMs = 50;
  static const int maxDurationMs = 5000;
  static const int durationStepMs = 50;

  /// Ceiling on `basePixelsPacked` plus every delta, in characters.
  ///
  /// The device flattens the asset into an ArduinoJson document before
  /// parsing, so this budget has to leave that buffer headroom. Raising it
  /// means raising `AssetCache.cpp`'s document size to match.
  static const int maxPackedChars = 8192;

  /// Packs [frames] into the Firestore wire format.
  ///
  /// Throws [AnimationCodecException] if the animation breaks a documented
  /// limit rather than emitting something the device would reject.
  static EncodedAnimation encode(List<AnimationFrameModel> frames) {
    if (frames.length < minFrames) {
      throw AnimationCodecException(
        'An animation needs at least $minFrames frames.',
      );
    }
    if (frames.length > maxFrames) {
      throw AnimationCodecException(
        'An animation cannot have more than $maxFrames frames.',
      );
    }

    for (var i = 0; i < frames.length; i++) {
      final duration = frames[i].durationMs;
      if (duration < minDurationMs || duration > maxDurationMs) {
        throw AnimationCodecException(
          'Frame ${i + 1} lasts ${duration}ms; each frame must be between '
          '${minDurationMs}ms and ${maxDurationMs}ms.',
        );
      }
    }

    if (!frames.any((frame) => frame.hasVisiblePixel)) {
      throw const AnimationCodecException(
        'An animation needs at least one visible pixel.',
      );
    }

    final base = _packFullFrame(frames.first.pixels);
    final deltas = <String>[];
    for (var i = 1; i < frames.length; i++) {
      deltas.add(_packDelta(frames[i - 1].pixels, frames[i].pixels));
    }

    final encoded = EncodedAnimation(
      basePixelsPacked: base,
      frameDeltasPacked: deltas,
      frameDurationsMs: frames.map((frame) => frame.durationMs).toList(),
    );

    if (encoded.packedLength > maxPackedChars) {
      throw AnimationCodecException(
        'This animation packs to ${encoded.packedLength} characters, over the '
        '$maxPackedChars character limit. Use fewer frames or change fewer '
        'pixels between them.',
      );
    }

    return encoded;
  }

  /// Rebuilds whole frames from the packed wire format.
  ///
  /// Returns an empty list when the payload is unusable, so a single corrupt
  /// asset degrades to "no frames" instead of throwing through a Firestore
  /// listener and taking the whole library down with it.
  static List<AnimationFrameModel> decode({
    required String basePixelsPacked,
    required List<String> frameDeltasPacked,
    required List<int> frameDurationsMs,
  }) {
    if (frameDurationsMs.isEmpty) return const [];
    if (frameDeltasPacked.length != frameDurationsMs.length - 1) {
      return const [];
    }

    final current = _unpackFullFrame(basePixelsPacked);
    if (current == null) return const [];

    final frames = <AnimationFrameModel>[
      AnimationFrameModel(pixels: current, durationMs: frameDurationsMs.first),
    ];

    for (var i = 0; i < frameDeltasPacked.length; i++) {
      if (!_applyDelta(current, frameDeltasPacked[i])) return const [];
      frames.add(
        AnimationFrameModel(
          pixels: current,
          durationMs: frameDurationsMs[i + 1],
        ),
      );
    }

    return frames;
  }

  /// Reads an animation written before [encodingName].
  ///
  /// Legacy frames are deltas against the base frame, not against each other,
  /// and each carries its own `delayMs`. Editing such an asset rewrites it in
  /// the packed format; nothing migrates in bulk.
  static List<AnimationFrameModel> decodeLegacy({
    required List<dynamic> basePixels,
    required List<dynamic> legacyFrames,
  }) {
    if (legacyFrames.isEmpty) return const [];

    final base = _unpackSparseEntries(basePixels);
    final frames = <AnimationFrameModel>[];

    for (final entry in legacyFrames) {
      if (entry is! Map) continue;
      final grid = AnimationFrameModel.copyGrid(base);
      final pixels = entry['pixels'];
      if (pixels is List) {
        for (final pixel in pixels) {
          final parsed = _readSparseEntry(pixel);
          if (parsed == null) continue;
          final (index, rgb) = parsed;
          grid[index ~/ 16][index % 16] = rgb == 0 ? 0 : 0xFF000000 | rgb;
        }
      }
      final delay = entry['delayMs'];
      frames.add(
        AnimationFrameModel(
          pixels: grid,
          durationMs: delay is int ? delay : AnimationFrameModel.defaultDurationMs,
        ),
      );
    }

    return frames;
  }

  static String _packFullFrame(List<List<int>> pixels) {
    final buffer = StringBuffer();
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final rgb = pixels[y][x] & 0xFFFFFF;
        if (rgb == 0) continue; // off pixels are simply absent from the base
        _writeGroup(buffer, y * 16 + x, rgb);
      }
    }
    return buffer.toString();
  }

  static String _packDelta(List<List<int>> from, List<List<int>> to) {
    final buffer = StringBuffer();
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final before = from[y][x] & 0xFFFFFF;
        final after = to[y][x] & 0xFFFFFF;
        if (before == after) continue;
        // 000000 is meaningful here: it is how a delta turns a pixel off.
        _writeGroup(buffer, y * 16 + x, after);
      }
    }
    return buffer.toString();
  }

  static void _writeGroup(StringBuffer buffer, int index, int rgb) {
    buffer.write(index.toRadixString(16).padLeft(2, '0'));
    buffer.write(rgb.toRadixString(16).padLeft(6, '0'));
  }

  static List<List<int>>? _unpackFullFrame(String packed) {
    final grid = AnimationFrameModel.emptyGrid();
    if (packed.isEmpty) return grid;
    return _applyDelta(grid, packed) ? grid : null;
  }

  /// Applies one packed transition onto [grid] in place.
  static bool _applyDelta(List<List<int>> grid, String packed) {
    if (packed.length % 8 != 0) return false;
    for (var i = 0; i < packed.length; i += 8) {
      final index = int.tryParse(packed.substring(i, i + 2), radix: 16);
      final rgb = int.tryParse(packed.substring(i + 2, i + 8), radix: 16);
      if (index == null || rgb == null || index < 0 || index >= 256) {
        return false;
      }
      grid[index ~/ 16][index % 16] = rgb == 0 ? 0 : 0xFF000000 | rgb;
    }
    return true;
  }

  static List<List<int>> _unpackSparseEntries(List<dynamic> entries) {
    final grid = AnimationFrameModel.emptyGrid();
    for (final entry in entries) {
      final parsed = _readSparseEntry(entry);
      if (parsed == null) continue;
      final (index, rgb) = parsed;
      grid[index ~/ 16][index % 16] = rgb == 0 ? 0 : 0xFF000000 | rgb;
    }
    return grid;
  }

  /// Reads `{"index": i, "color": c}` or the older `[i, c]` pair.
  static (int, int)? _readSparseEntry(dynamic entry) {
    int? index;
    int? rgb;
    if (entry is Map) {
      index = entry['index'] as int?;
      rgb = entry['color'] as int?;
    } else if (entry is List && entry.length >= 2) {
      index = entry[0] as int?;
      rgb = entry[1] as int?;
    }
    if (index == null || rgb == null || index < 0 || index >= 256) return null;
    return (index, rgb);
  }
}
