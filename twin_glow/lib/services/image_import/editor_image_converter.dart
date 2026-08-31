import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// How a source image is reduced to the editor's 16x16 grid.
enum ImageConversionMode { pixelArt, photo }

/// Thrown when a selected image or animation cannot become an editor asset.
class ImageImportFailure implements Exception {
  final String message;

  const ImageImportFailure(this.message);

  @override
  String toString() => message;
}

/// The pixel maths shared by still-image import and animation import.
///
/// Both importers have to land on byte-identical grids for the same source
/// pixels - an animation whose frames converted differently from the same
/// image would preview one way and save another. Keeping the sampling,
/// transparency threshold and colour bucketing in one place is what guarantees
/// that; the importers above only differ in how they get an [img.Image] here.
class EditorImageConverter {
  const EditorImageConverter._();

  static const int editorSize = 16;

  /// Alpha at or below this reads as off, matching the editor's `0` pixel.
  static const int transparentThreshold = 16;

  static const int _maxSuggestedColors = 64;

  /// Whether [source] looks like scaled-up pixel art rather than a photo.
  static ImageConversionMode suggestMode(img.Image source) {
    if (source.width == editorSize && source.height == editorSize) {
      return ImageConversionMode.pixelArt;
    }
    if (_isCleanMultiple(source) && _hasLimitedColorCount(source)) {
      return ImageConversionMode.pixelArt;
    }
    return ImageConversionMode.photo;
  }

  /// Hard-edged reduction: exact pixels, dominant cell colour, or nearest.
  static List<List<int>> toPixelArt(img.Image source) {
    if (source.width == editorSize && source.height == editorSize) {
      return _grid(source);
    }
    if (_isCleanMultiple(source)) {
      return _downsampleDominantCells(source);
    }
    return _grid(
      img.copyResize(
        source,
        width: editorSize,
        height: editorSize,
        interpolation: img.Interpolation.nearest,
      ),
    );
  }

  /// Smooth reduction for continuous-tone sources.
  static List<List<int>> toPhoto(img.Image source) {
    return _grid(
      img.copyResize(
        source,
        width: editorSize,
        height: editorSize,
        interpolation: img.Interpolation.average,
      ),
    );
  }

  static List<List<int>> dataFor(img.Image source, ImageConversionMode mode) {
    return mode == ImageConversionMode.pixelArt
        ? toPixelArt(source)
        : toPhoto(source);
  }

  /// Composites onto black and drops alpha, because the panel has no alpha
  /// channel: a half-transparent pixel has to become the colour it would look
  /// like over an unlit LED.
  static int toEditorColor(img.Pixel pixel) {
    final alpha = pixel.a.round().clamp(0, 255);
    if (alpha <= transparentThreshold) return 0;

    final red = (pixel.r * alpha / 255).round().clamp(0, 255);
    final green = (pixel.g * alpha / 255).round().clamp(0, 255);
    final blue = (pixel.b * alpha / 255).round().clamp(0, 255);
    return 0xFF000000 | (red << 16) | (green << 8) | blue;
  }

  static bool _isCleanMultiple(img.Image source) =>
      source.width >= editorSize &&
      source.height >= editorSize &&
      source.width % editorSize == 0 &&
      source.height % editorSize == 0;

  static List<List<int>> _grid(img.Image source) {
    return List.generate(
      editorSize,
      (y) => List.generate(
        editorSize,
        (x) => toEditorColor(source.getPixel(x, y)),
      ),
    );
  }

  static bool _hasLimitedColorCount(img.Image source) {
    final colors = <int>{};
    final sampleStride = math.max(
      1,
      math.sqrt((source.width * source.height) / 4096).floor(),
    );

    for (var y = 0; y < source.height; y += sampleStride) {
      for (var x = 0; x < source.width; x += sampleStride) {
        colors.add(bucketKey(toEditorColor(source.getPixel(x, y))));
        if (colors.length > _maxSuggestedColors) return false;
      }
    }
    return true;
  }

  static List<List<int>> _downsampleDominantCells(img.Image source) {
    final cellWidth = source.width ~/ editorSize;
    final cellHeight = source.height ~/ editorSize;

    return List.generate(editorSize, (row) {
      return List.generate(editorSize, (column) {
        final buckets = <int, _ColorBucket>{};
        final startX = column * cellWidth;
        final startY = row * cellHeight;
        final centerColor = toEditorColor(
          source.getPixel(startX + cellWidth ~/ 2, startY + cellHeight ~/ 2),
        );
        final centerKey = bucketKey(centerColor);

        for (var y = startY; y < startY + cellHeight; y++) {
          for (var x = startX; x < startX + cellWidth; x++) {
            final color = toEditorColor(source.getPixel(x, y));
            buckets.putIfAbsent(bucketKey(color), _ColorBucket.new).add(color);
          }
        }

        var winningKey = centerKey;
        var winningCount = -1;
        for (final entry in buckets.entries) {
          if (entry.value.count > winningCount ||
              (entry.value.count == winningCount && entry.key == centerKey)) {
            winningKey = entry.key;
            winningCount = entry.value.count;
          }
        }
        return buckets[winningKey]!.averageColor;
      });
    });
  }

  /// Groups near-identical colours into 5-bit-per-channel buckets, so noise in
  /// a scaled-up sprite does not read as a distinct colour.
  static int bucketKey(int editorColor) {
    if (editorColor == 0) return -1;
    final red = (editorColor >> 16) & 0xFF;
    final green = (editorColor >> 8) & 0xFF;
    final blue = editorColor & 0xFF;
    return ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3);
  }
}

class _ColorBucket {
  int count = 0;
  int red = 0;
  int green = 0;
  int blue = 0;
  int transparentCount = 0;

  void add(int color) {
    count++;
    if (color == 0) {
      transparentCount++;
      return;
    }
    red += (color >> 16) & 0xFF;
    green += (color >> 8) & 0xFF;
    blue += color & 0xFF;
  }

  int get averageColor {
    if (transparentCount == count) return 0;
    final opaqueCount = count - transparentCount;
    return 0xFF000000 |
        ((red ~/ opaqueCount) << 16) |
        ((green ~/ opaqueCount) << 8) |
        (blue ~/ opaqueCount);
  }
}
