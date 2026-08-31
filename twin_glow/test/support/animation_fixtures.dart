import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One frame of a hand-built GIF fixture.
class GifFixtureFrame {
  /// Row-major palette indices, `width * height` entries.
  final List<int> indices;
  final int x;
  final int y;
  final int width;
  final int height;

  /// Hundredths of a second, as GIF stores it.
  final int delayCentis;

  /// 0 none, 1 do not dispose, 2 restore to background, 3 restore to previous.
  final int disposal;

  final int? transparentIndex;

  const GifFixtureFrame({
    required this.indices,
    required this.width,
    required this.height,
    this.x = 0,
    this.y = 0,
    this.delayCentis = 10,
    this.disposal = 1,
    this.transparentIndex,
  });
}

/// Builds GIF bytes directly, because `encodeGif` only ever writes
/// full-canvas frames: partial frames, offsets, and disposal - the parts of
/// the format that actually need composing - cannot be produced any other way.
Uint8List buildGif({
  required int width,
  required int height,
  required List<List<int>> palette,
  required List<GifFixtureFrame> frames,
}) {
  final bytes = <int>[];

  var paletteBits = 1;
  while ((1 << (paletteBits + 1)) < palette.length) {
    paletteBits++;
  }
  final paletteSize = 1 << (paletteBits + 1);

  bytes.addAll('GIF89a'.codeUnits);
  bytes
    ..addAll(_uint16(width))
    ..addAll(_uint16(height))
    ..add(0x80 | paletteBits) // global colour table present
    ..add(0)
    ..add(0);

  for (var i = 0; i < paletteSize; i++) {
    final color = i < palette.length ? palette[i] : const [0, 0, 0];
    bytes.addAll([color[0], color[1], color[2]]);
  }

  for (final frame in frames) {
    final transparent = frame.transparentIndex;
    bytes
      ..addAll([0x21, 0xF9, 0x04])
      ..add((frame.disposal << 2) | (transparent != null ? 1 : 0))
      ..addAll(_uint16(frame.delayCentis))
      ..add(transparent ?? 0)
      ..add(0x00);

    bytes
      ..add(0x2C)
      ..addAll(_uint16(frame.x))
      ..addAll(_uint16(frame.y))
      ..addAll(_uint16(frame.width))
      ..addAll(_uint16(frame.height))
      ..add(0x00);

    bytes.addAll(_uncompressedLzw(frame.indices));
  }

  bytes.add(0x3B);
  return Uint8List.fromList(bytes);
}

/// Emits LZW that never compresses.
///
/// With a minimum code size of 7 every code is exactly 8 bits, so the stream
/// is byte-aligned and needs no bit packer. Re-clearing the dictionary every
/// 100 literals keeps the next code below 256, which is what holds the width
/// at 8 bits.
List<int> _uncompressedLzw(List<int> indices) {
  const minCodeSize = 7;
  const clearCode = 1 << minCodeSize;
  const endCode = clearCode + 1;
  const literalsPerClear = 100;

  final codes = <int>[];
  for (var i = 0; i < indices.length; i++) {
    if (i % literalsPerClear == 0) codes.add(clearCode);
    codes.add(indices[i]);
  }
  codes
    ..add(clearCode)
    ..add(endCode);

  final out = <int>[minCodeSize];
  for (var offset = 0; offset < codes.length; offset += 255) {
    final end = (offset + 255).clamp(0, codes.length);
    out
      ..add(end - offset)
      ..addAll(codes.sublist(offset, end));
  }
  out.add(0x00);
  return out;
}

List<int> _uint16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

List<int> _uint24(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
];

/// Wraps single-frame lossless WebP payloads in an animated container.
///
/// `encodeWebP` writes one still frame only, so the VP8X/ANIM/ANMF envelope
/// has to be assembled here to get an animated WebP at all.
Uint8List buildAnimatedWebP({
  required List<img.Image> frames,
  required List<int> durationsMs,
}) {
  final canvasWidth = frames.first.width;
  final canvasHeight = frames.first.height;
  final body = <int>[];

  body
    ..addAll(
      _riffChunk('VP8X', [
        0x02, // animation flag
        0, 0, 0, // reserved
        ..._uint24(canvasWidth - 1),
        ..._uint24(canvasHeight - 1),
      ]),
    )
    ..addAll(_riffChunk('ANIM', [0, 0, 0, 0, 0, 0])); // bg colour, loop forever

  for (var i = 0; i < frames.length; i++) {
    final encoded = img.encodeWebP(frames[i]);
    final payload = _extractRiffChunk(encoded, 'VP8L');
    body.addAll(
      _riffChunk('ANMF', [
        ..._uint24(0), // x / 2
        ..._uint24(0), // y / 2
        ..._uint24(frames[i].width - 1),
        ..._uint24(frames[i].height - 1),
        ..._uint24(durationsMs[i]),
        0x00, // no disposal, no alpha blending
        ..._riffChunk('VP8L', payload),
      ]),
    );
  }

  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._uint32(4 + body.length),
    ...'WEBP'.codeUnits,
    ...body,
  ]);
}

List<int> _riffChunk(String tag, List<int> payload) {
  return [
    ...tag.codeUnits,
    ..._uint32(payload.length),
    ...payload,
    if (payload.length.isOdd) 0,
  ];
}

List<int> _extractRiffChunk(Uint8List bytes, String tag) {
  var offset = 12; // past RIFF <size> WEBP
  while (offset + 8 <= bytes.length) {
    final name = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    if (name == tag) {
      return bytes.sublist(offset + 8, offset + 8 + size);
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('No $tag chunk in the encoded WebP.');
}

List<int> _uint32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

/// A solid-colour frame, the building block for the simple fixtures.
img.Image solidFrame(
  int size,
  int red,
  int green,
  int blue, {
  int alpha = 255,
  int durationMs = 100,
}) {
  final frame = img.Image(width: size, height: size, numChannels: 4);
  img.fill(frame, color: img.ColorRgba8(red, green, blue, alpha));
  frame.frameDuration = durationMs;
  return frame;
}

/// An APNG built from [frames]; `encodePng` writes acTL/fcTL for a
/// multi-frame image.
Uint8List buildApng(List<img.Image> frames) {
  final first = frames.first;
  for (final frame in frames.skip(1)) {
    first.addFrame(frame);
  }
  return img.encodePng(first);
}
