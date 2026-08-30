import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum ImageConversionMode { pixelArt, photo }

class ImageSourceInfo {
  final int width;
  final int height;
  final img.ImageFormat format;

  const ImageSourceInfo({
    required this.width,
    required this.height,
    required this.format,
  });
}

class ImageConversionResult {
  final List<List<int>> pixelArtData;
  final List<List<int>> photoData;
  final ImageConversionMode suggestedMode;
  final int sourceWidth;
  final int sourceHeight;

  const ImageConversionResult({
    required this.pixelArtData,
    required this.photoData,
    required this.suggestedMode,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  List<List<int>> dataFor(ImageConversionMode mode) {
    return mode == ImageConversionMode.pixelArt ? pixelArtData : photoData;
  }
}

class ImageImportFailure implements Exception {
  final String message;

  const ImageImportFailure(this.message);

  @override
  String toString() => message;
}

class ImageImportConverter {
  static const int editorSize = 16;
  static const int transparentThreshold = 16;
  static const int maxSourcePixels = 50000000;
  static const int _maxSuggestedColors = 64;

  static ImageSourceInfo inspectSource(Uint8List bytes) {
    final format = img.findFormatForData(bytes);
    if (format != img.ImageFormat.png &&
        format != img.ImageFormat.jpg &&
        format != img.ImageFormat.webp) {
      throw const ImageImportFailure(
        'Unsupported image format. Choose a PNG, JPG, JPEG, or WebP image.',
      );
    }

    final decoder = img.createDecoderForFormat(format);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      throw const ImageImportFailure(
        'This image is corrupted or could not be decoded.',
      );
    }

    if (info.width * info.height > maxSourcePixels) {
      throw const ImageImportFailure(
        'This image is too large. Choose an image smaller than 50 megapixels.',
      );
    }

    return ImageSourceInfo(
      width: info.width,
      height: info.height,
      format: format,
    );
  }

  static ImageConversionResult convertCroppedImage(Uint8List bytes) {
    final sourceInfo = inspectSource(bytes);
    img.Image? decoded;

    switch (sourceInfo.format) {
      case img.ImageFormat.jpg:
        decoded = img.decodeJpg(bytes);
      case img.ImageFormat.png:
        decoded = img.decodePng(bytes, frame: 0);
      case img.ImageFormat.webp:
        decoded = img.decodeWebP(bytes, frame: 0);
      default:
        decoded = null;
    }

    if (decoded == null) {
      throw const ImageImportFailure(
        'This image is corrupted or could not be decoded.',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    if (oriented.width != oriented.height) {
      throw const ImageImportFailure(
        'The selected crop is not square. Please crop the image again.',
      );
    }

    final suggestedMode = _suggestMode(oriented);
    return ImageConversionResult(
      pixelArtData: _convertPixelArt(oriented),
      photoData: _convertPhoto(oriented),
      suggestedMode: suggestedMode,
      sourceWidth: oriented.width,
      sourceHeight: oriented.height,
    );
  }

  static ImageConversionMode _suggestMode(img.Image source) {
    if (source.width == editorSize && source.height == editorSize) {
      return ImageConversionMode.pixelArt;
    }

    final isCleanMultiple =
        source.width >= editorSize &&
        source.height >= editorSize &&
        source.width % editorSize == 0 &&
        source.height % editorSize == 0;
    if (isCleanMultiple && _hasLimitedColorCount(source)) {
      return ImageConversionMode.pixelArt;
    }
    return ImageConversionMode.photo;
  }

  static bool _hasLimitedColorCount(img.Image source) {
    final colors = <int>{};
    final sampleStride = math.max(
      1,
      math.sqrt((source.width * source.height) / 4096).floor(),
    );

    for (var y = 0; y < source.height; y += sampleStride) {
      for (var x = 0; x < source.width; x += sampleStride) {
        final editorColor = _toEditorColor(source.getPixel(x, y));
        colors.add(_bucketKey(editorColor));
        if (colors.length > _maxSuggestedColors) return false;
      }
    }
    return true;
  }

  static List<List<int>> _convertPixelArt(img.Image source) {
    if (source.width == editorSize && source.height == editorSize) {
      return List.generate(
        editorSize,
        (y) => List.generate(
          editorSize,
          (x) => _toEditorColor(source.getPixel(x, y)),
        ),
      );
    }

    final isCleanMultiple =
        source.width >= editorSize &&
        source.height >= editorSize &&
        source.width % editorSize == 0 &&
        source.height % editorSize == 0;
    if (isCleanMultiple) {
      return _downsampleDominantCells(source);
    }

    final resized = img.copyResize(
      source,
      width: editorSize,
      height: editorSize,
      interpolation: img.Interpolation.nearest,
    );
    return List.generate(
      editorSize,
      (y) => List.generate(
        editorSize,
        (x) => _toEditorColor(resized.getPixel(x, y)),
      ),
    );
  }

  static List<List<int>> _downsampleDominantCells(img.Image source) {
    final cellWidth = source.width ~/ editorSize;
    final cellHeight = source.height ~/ editorSize;

    return List.generate(editorSize, (row) {
      return List.generate(editorSize, (column) {
        final buckets = <int, _ColorBucket>{};
        final startX = column * cellWidth;
        final startY = row * cellHeight;
        final centerColor = _toEditorColor(
          source.getPixel(startX + cellWidth ~/ 2, startY + cellHeight ~/ 2),
        );
        final centerKey = _bucketKey(centerColor);

        for (var y = startY; y < startY + cellHeight; y++) {
          for (var x = startX; x < startX + cellWidth; x++) {
            final color = _toEditorColor(source.getPixel(x, y));
            final key = _bucketKey(color);
            buckets.putIfAbsent(key, _ColorBucket.new).add(color);
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

  static List<List<int>> _convertPhoto(img.Image source) {
    final resized = img.copyResize(
      source,
      width: editorSize,
      height: editorSize,
      interpolation: img.Interpolation.average,
    );
    return List.generate(
      editorSize,
      (y) => List.generate(
        editorSize,
        (x) => _toEditorColor(resized.getPixel(x, y)),
      ),
    );
  }

  static int _toEditorColor(img.Pixel pixel) {
    final alpha = pixel.a.round().clamp(0, 255);
    if (alpha <= transparentThreshold) return 0;

    final red = (pixel.r * alpha / 255).round().clamp(0, 255);
    final green = (pixel.g * alpha / 255).round().clamp(0, 255);
    final blue = (pixel.b * alpha / 255).round().clamp(0, 255);
    return 0xFF000000 | (red << 16) | (green << 8) | blue;
  }

  static int _bucketKey(int editorColor) {
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
