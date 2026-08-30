import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/codecs/animation_codec.dart';
import 'package:twin_glow/core/models/asset_model.dart';

AnimationFrameModel frameWith(
  Map<int, int> litPixels, {
  int durationMs = 200,
}) {
  final grid = AnimationFrameModel.emptyGrid();
  litPixels.forEach((index, rgb) {
    grid[index ~/ 16][index % 16] = rgb == 0 ? 0 : 0xFF000000 | rgb;
  });
  return AnimationFrameModel(pixels: grid, durationMs: durationMs);
}

void main() {
  group('AnimationCodec.encode', () {
    test('packs the first frame as IIRRGGBB groups', () {
      final encoded = AnimationCodec.encode([
        frameWith({0: 0xFF0000, 17: 0x00FF00}),
        frameWith({0: 0xFF0000, 17: 0x00FF00}),
      ]);

      expect(encoded.basePixelsPacked, '00ff00001100ff00');
      expect(encoded.frameDeltasPacked, ['']);
      expect(encoded.frameDurationsMs, [200, 200]);
      expect(encoded.frameCount, 2);
    });

    test('encodes only what changed between consecutive frames', () {
      final encoded = AnimationCodec.encode([
        frameWith({0: 0xFF0000, 1: 0x00FF00}),
        frameWith({0: 0xFF0000, 1: 0x0000FF}),
      ]);

      // Pixel 0 is unchanged, so only pixel 1 appears in the delta.
      expect(encoded.frameDeltasPacked.single, '010000ff');
    });

    test('clears a pixel with a 000000 group', () {
      final encoded = AnimationCodec.encode([
        frameWith({5: 0xFFFFFF}),
        frameWith({}),
      ]);

      expect(encoded.basePixelsPacked, '05ffffff');
      expect(encoded.frameDeltasPacked.single, '05000000');
    });

    test('deltas are relative to the preceding frame, not the base', () {
      final encoded = AnimationCodec.encode([
        frameWith({0: 0x111111}),
        frameWith({0: 0x222222}),
        frameWith({0: 0x333333}),
      ]);

      expect(encoded.frameDeltasPacked, ['00222222', '00333333']);
    });

    test('rejects fewer than two frames', () {
      expect(
        () => AnimationCodec.encode([frameWith({0: 0xFFFFFF})]),
        throwsA(isA<AnimationCodecException>()),
      );
    });

    test('accepts exactly the frame-count boundaries', () {
      final two = List.generate(2, (_) => frameWith({0: 0xFFFFFF}));
      final sixteen = List.generate(16, (_) => frameWith({0: 0xFFFFFF}));

      expect(AnimationCodec.encode(two).frameCount, 2);
      expect(AnimationCodec.encode(sixteen).frameCount, 16);
      expect(
        () => AnimationCodec.encode(
          List.generate(17, (_) => frameWith({0: 0xFFFFFF})),
        ),
        throwsA(isA<AnimationCodecException>()),
      );
    });

    test('accepts exactly the duration boundaries and rejects beyond them', () {
      expect(
        AnimationCodec.encode([
          frameWith({0: 0xFFFFFF}, durationMs: 50),
          frameWith({0: 0xFFFFFF}, durationMs: 5000),
        ]).frameDurationsMs,
        [50, 5000],
      );
      expect(
        () => AnimationCodec.encode([
          frameWith({0: 0xFFFFFF}, durationMs: 49),
          frameWith({0: 0xFFFFFF}),
        ]),
        throwsA(isA<AnimationCodecException>()),
      );
      expect(
        () => AnimationCodec.encode([
          frameWith({0: 0xFFFFFF}, durationMs: 5001),
          frameWith({0: 0xFFFFFF}),
        ]),
        throwsA(isA<AnimationCodecException>()),
      );
    });

    test('rejects an animation with no visible pixel', () {
      expect(
        () => AnimationCodec.encode([frameWith({}), frameWith({})]),
        throwsA(isA<AnimationCodecException>()),
      );
    });

    test('rejects a payload over the packed-character limit', () {
      // Alternating full frames: every pixel changes on every transition.
      final dense = <AnimationFrameModel>[];
      for (var i = 0; i < 16; i++) {
        dense.add(
          frameWith({
            for (var p = 0; p < 256; p++) p: i.isEven ? 0xFF0000 : 0x00FF00,
          }),
        );
      }

      expect(
        () => AnimationCodec.encode(dense),
        throwsA(
          isA<AnimationCodecException>().having(
            (e) => e.message,
            'message',
            contains('character limit'),
          ),
        ),
      );
    });
  });

  group('AnimationCodec.decode', () {
    test('round-trips frames, order and durations', () {
      final original = [
        frameWith({0: 0xFF0000, 255: 0x00FF00}, durationMs: 100),
        frameWith({0: 0x0000FF}, durationMs: 350),
        frameWith({128: 0xABCDEF}, durationMs: 5000),
      ];

      final encoded = AnimationCodec.encode(original);
      final decoded = AnimationCodec.decode(
        basePixelsPacked: encoded.basePixelsPacked,
        frameDeltasPacked: encoded.frameDeltasPacked,
        frameDurationsMs: encoded.frameDurationsMs,
      );

      expect(decoded.length, 3);
      for (var i = 0; i < original.length; i++) {
        expect(decoded[i].durationMs, original[i].durationMs);
        expect(decoded[i].pixels, original[i].pixels);
      }
    });

    test('round-trips a sparse frame followed by a dense frame', () {
      final original = [
        frameWith({3: 0x010203}, durationMs: 60),
        frameWith({for (var p = 0; p < 256; p++) p: 0x0A0B0C}, durationMs: 60),
      ];

      final encoded = AnimationCodec.encode(original);
      final decoded = AnimationCodec.decode(
        basePixelsPacked: encoded.basePixelsPacked,
        frameDeltasPacked: encoded.frameDeltasPacked,
        frameDurationsMs: encoded.frameDurationsMs,
      );

      expect(decoded[1].pixels, original[1].pixels);
    });

    test('applies deltas cumulatively', () {
      final decoded = AnimationCodec.decode(
        basePixelsPacked: '00ff0000',
        frameDeltasPacked: const ['0100ff00', '020000ff'],
        frameDurationsMs: const [100, 100, 100],
      );

      // Each frame keeps everything the previous frame drew.
      expect(decoded[2].pixels[0][0], 0xFFFF0000);
      expect(decoded[2].pixels[0][1], 0xFF00FF00);
      expect(decoded[2].pixels[0][2], 0xFF0000FF);
    });

    test('a 000000 delta group turns the pixel off', () {
      final decoded = AnimationCodec.decode(
        basePixelsPacked: '05ffffff',
        frameDeltasPacked: const ['05000000'],
        frameDurationsMs: const [100, 100],
      );

      expect(decoded[0].pixels[0][5], 0xFFFFFFFF);
      expect(decoded[1].pixels[0][5], 0);
    });

    test('returns no frames when durations and deltas disagree', () {
      expect(
        AnimationCodec.decode(
          basePixelsPacked: '00ff0000',
          frameDeltasPacked: const ['0100ff00'],
          frameDurationsMs: const [100, 100, 100],
        ),
        isEmpty,
      );
    });

    test('returns no frames for a malformed packed string', () {
      expect(
        AnimationCodec.decode(
          basePixelsPacked: 'abc',
          frameDeltasPacked: const [''],
          frameDurationsMs: const [100, 100],
        ),
        isEmpty,
      );
    });
  });

  group('AnimationCodec.decodeLegacy', () {
    test('reads DELTA_SPARSE_I16_RGB888 frames as base-relative', () {
      final frames = AnimationCodec.decodeLegacy(
        basePixels: [
          {'index': 0, 'color': 0xFF0000},
        ],
        legacyFrames: [
          {
            'delayMs': 120,
            'pixels': [
              {'index': 1, 'color': 0x00FF00},
            ],
          },
          {
            'delayMs': 240,
            'pixels': [
              {'index': 0, 'color': 0},
            ],
          },
        ],
      );

      expect(frames.length, 2);
      expect(frames[0].durationMs, 120);
      // Legacy frame 1 is base + its own delta.
      expect(frames[0].pixels[0][0], 0xFFFF0000);
      expect(frames[0].pixels[0][1], 0xFF00FF00);
      // Frame 2 is base + its own delta only - frame 1's change is not carried.
      expect(frames[1].durationMs, 240);
      expect(frames[1].pixels[0][0], 0);
      expect(frames[1].pixels[0][1], 0);
    });

    test('re-encodes a decoded legacy animation into the packed format', () {
      final frames = AnimationCodec.decodeLegacy(
        basePixels: [
          [0, 0xFF0000],
        ],
        legacyFrames: [
          {'delayMs': 100, 'pixels': []},
          {
            'delayMs': 100,
            'pixels': [
              [5, 0x0000FF],
            ],
          },
        ],
      );

      final encoded = AnimationCodec.encode(frames);
      expect(encoded.basePixelsPacked, '00ff0000');
      expect(encoded.frameDeltasPacked.single, '050000ff');
    });
  });
}
