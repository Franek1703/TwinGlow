import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'editor_image_converter.dart';

export 'editor_image_converter.dart'
    show ImageConversionMode, ImageImportFailure;

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

/// Turns one still image into the editor's 16x16 grid.
///
/// The pixel maths lives in [EditorImageConverter] so animation import lands
/// on identical grids for identical source pixels.
class ImageImportConverter {
  static const int editorSize = EditorImageConverter.editorSize;
  static const int transparentThreshold =
      EditorImageConverter.transparentThreshold;
  static const int maxSourcePixels = 50000000;

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

    return ImageConversionResult(
      pixelArtData: EditorImageConverter.toPixelArt(oriented),
      photoData: EditorImageConverter.toPhoto(oriented),
      suggestedMode: EditorImageConverter.suggestMode(oriented),
      sourceWidth: oriented.width,
      sourceHeight: oriented.height,
    );
  }
}
