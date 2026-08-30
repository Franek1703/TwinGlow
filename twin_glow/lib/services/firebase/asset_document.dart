import '../../core/codecs/animation_codec.dart';
import '../../core/models/asset_model.dart';

/// The encoding-specific half of an `/assets/{assetId}` document.
///
/// Split out from the repository so the exact field map can be asserted
/// without a Firestore connection. Deletions travel as plain field names; the
/// repository turns them into `FieldValue.delete()` on an update.
class AssetDocumentFields {
  /// Fields to write.
  final Map<String, dynamic> values;

  /// Fields that must not survive this write.
  ///
  /// A document keeps whatever it was last written with, so an image saved
  /// over an animation would otherwise leave `frameDeltasPacked` behind and
  /// vice versa - and the leftovers are exactly the bulk that pushes the
  /// document past what the device can buffer.
  final List<String> obsoleteFieldNames;

  const AssetDocumentFields({
    required this.values,
    required this.obsoleteFieldNames,
  });
}

/// Fields written before the packed encodings existed. Every write clears them,
/// which is what actually shrinks a migrated document.
const List<String> _legacyFieldNames = ['pixels', 'basePixels', 'frames'];

const List<String> _imageFieldNames = ['pixelsPacked'];

const List<String> _animationFieldNames = [
  'basePixelsPacked',
  'frameDeltasPacked',
  'frameDurationsMs',
  'frameCount',
  'loop',
];

/// Converts a full 16x16 grid to SPARSE_PACKED_V1: one string of fixed-width
/// 8-character groups, "IIRRGGBB" per non-black pixel, where II is the index
/// (y*16 + x, 0-255) and RRGGBB is the colour.
///
/// This exists because the previous per-pixel map format produced Firestore
/// documents around 23KB, which the device's Firebase client silently failed
/// to buffer. The packed form is roughly 1KB for the same image.
String packImageGrid(List<List<int>>? pixelData) {
  if (pixelData == null || pixelData.isEmpty) return '';

  final buffer = StringBuffer();

  for (int y = 0; y < pixelData.length && y < 16; y++) {
    final row = pixelData[y];
    for (int x = 0; x < row.length && x < 16; x++) {
      final color = row[x];
      // Skip black pixels (0 or transparent)
      if (color != 0) {
        // Convert ARGB to RGB888 (remove alpha channel)
        final rgb888 = color & 0xFFFFFF;
        final index = y * 16 + x;
        buffer.write(index.toRadixString(16).padLeft(2, '0'));
        buffer.write(rgb888.toRadixString(16).padLeft(6, '0'));
      }
    }
  }

  return buffer.toString();
}

/// Builds the pixel fields for [asset], plus the fields its write replaces.
///
/// Images stay on SPARSE_PACKED_V1. Animations use DELTA_SPARSE_PACKED_V1,
/// which reuses the same IIRRGGBB grouping so the device parses both with one
/// primitive. Throws [AnimationCodecException] for an animation that breaks a
/// documented limit, so the save fails rather than reaching the device
/// truncated.
AssetDocumentFields buildAssetPixelFields(AssetModel asset) {
  if (asset.type != AssetType.animation) {
    return AssetDocumentFields(
      values: {
        'encoding': 'SPARSE_PACKED_V1',
        'pixelsPacked': packImageGrid(asset.pixelData),
      },
      obsoleteFieldNames: [..._legacyFieldNames, ..._animationFieldNames],
    );
  }

  final encoded = AnimationCodec.encode(asset.frames ?? const []);
  return AssetDocumentFields(
    values: {
      'encoding': AnimationCodec.encodingName,
      'basePixelsPacked': encoded.basePixelsPacked,
      'frameDeltasPacked': encoded.frameDeltasPacked,
      'frameDurationsMs': encoded.frameDurationsMs,
      'frameCount': encoded.frameCount,
      'loop': true,
    },
    obsoleteFieldNames: [..._legacyFieldNames, ..._imageFieldNames],
  );
}
