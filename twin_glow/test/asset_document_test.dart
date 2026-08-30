import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/codecs/animation_codec.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/services/firebase/asset_document.dart';

List<List<int>> gridWith(Map<int, int> litPixels) {
  final grid = AnimationFrameModel.emptyGrid();
  litPixels.forEach((index, rgb) {
    grid[index ~/ 16][index % 16] = 0xFF000000 | rgb;
  });
  return grid;
}

AnimationFrameModel frameWith(Map<int, int> lit, {int durationMs = 200}) =>
    AnimationFrameModel(pixels: gridWith(lit), durationMs: durationMs);

void main() {
  group('image assets', () {
    test('write the packed image fields and nothing animation-shaped', () {
      final fields = buildAssetPixelFields(
        AssetModel(
          id: 'a1',
          name: 'Heart',
          type: AssetType.image,
          pixelData: gridWith({0: 0xFF0000, 17: 0x00FF00}),
        ),
      );

      expect(fields.values, {
        'encoding': 'SPARSE_PACKED_V1',
        'pixelsPacked': '00ff00001100ff00',
      });
    });

    test('clear the legacy and animation fields they replace', () {
      final fields = buildAssetPixelFields(
        AssetModel(
          id: 'a1',
          name: 'Heart',
          type: AssetType.image,
          pixelData: gridWith({0: 0xFF0000}),
        ),
      );

      expect(
        fields.obsoleteFieldNames,
        containsAll([
          'pixels',
          'basePixels',
          'frames',
          'basePixelsPacked',
          'frameDeltasPacked',
          'frameDurationsMs',
          'frameCount',
          'loop',
        ]),
      );
      // The field it is about to write must not also be deleted.
      expect(fields.obsoleteFieldNames, isNot(contains('pixelsPacked')));
    });
  });

  group('animation assets', () {
    test('write the packed animation fields', () {
      final fields = buildAssetPixelFields(
        AssetModel(
          id: 'a2',
          name: 'Blink',
          type: AssetType.animation,
          frames: [
            frameWith({0: 0xFF0000}, durationMs: 100),
            frameWith({0: 0x00FF00}, durationMs: 250),
          ],
        ),
      );

      expect(fields.values, {
        'encoding': 'DELTA_SPARSE_PACKED_V1',
        'basePixelsPacked': '00ff0000',
        'frameDeltasPacked': ['0000ff00'],
        'frameDurationsMs': [100, 250],
        'frameCount': 2,
        'loop': true,
      });
    });

    test('clear the legacy and image fields they replace', () {
      final fields = buildAssetPixelFields(
        AssetModel(
          id: 'a2',
          name: 'Blink',
          type: AssetType.animation,
          frames: [frameWith({0: 0xFF0000}), frameWith({0: 0x00FF00})],
        ),
      );

      expect(
        fields.obsoleteFieldNames,
        containsAll(['pixels', 'basePixels', 'frames', 'pixelsPacked']),
      );
      for (final written in fields.values.keys) {
        expect(fields.obsoleteFieldNames, isNot(contains(written)));
      }
    });

    test('rewrite a legacy animation in the packed format', () {
      // What a DELTA_SPARSE_I16_RGB888 document decodes to.
      final legacyFrames = AnimationCodec.decodeLegacy(
        basePixels: [
          {'index': 0, 'color': 0xFF0000},
        ],
        legacyFrames: [
          {'delayMs': 120, 'pixels': []},
          {
            'delayMs': 120,
            'pixels': [
              {'index': 5, 'color': 0x0000FF},
            ],
          },
        ],
      );

      final fields = buildAssetPixelFields(
        AssetModel(
          id: 'legacy',
          name: 'Old',
          type: AssetType.animation,
          frames: legacyFrames,
        ),
      );

      expect(fields.values['encoding'], 'DELTA_SPARSE_PACKED_V1');
      expect(fields.values['basePixelsPacked'], '00ff0000');
      expect(fields.values['frameDeltasPacked'], ['050000ff']);
      // The legacy arrays go away in the same write.
      expect(
        fields.obsoleteFieldNames,
        containsAll(['basePixels', 'frames']),
      );
    });

    test('refuse to build fields for an over-limit animation', () {
      final dense = List.generate(
        16,
        (i) => frameWith({
          for (var p = 0; p < 256; p++) p: i.isEven ? 0xFF0000 : 0x00FF00,
        }),
      );

      expect(
        () => buildAssetPixelFields(
          AssetModel(
            id: 'big',
            name: 'Too big',
            type: AssetType.animation,
            frames: dense,
          ),
        ),
        throwsA(isA<AnimationCodecException>()),
      );
    });
  });

  test('FieldValue.delete() is available for every obsolete field name', () {
    // The repository maps obsoleteFieldNames onto FieldValue.delete() in the
    // same update() call that writes the new encoding.
    final fields = buildAssetPixelFields(
      AssetModel(
        id: 'a1',
        name: 'Heart',
        type: AssetType.image,
        pixelData: gridWith({0: 0xFF0000}),
      ),
    );

    final update = <String, dynamic>{
      ...fields.values,
      for (final name in fields.obsoleteFieldNames) name: FieldValue.delete(),
    };

    expect(update['pixelsPacked'], '00ff0000');
    expect(update['pixels'], isA<FieldValue>());
    expect(update['frameDeltasPacked'], isA<FieldValue>());
  });
}
