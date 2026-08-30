import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:twin_glow/services/image_import/image_import_converter.dart';

void main() {
  group('ImageImportConverter', () {
    test('preserves an exact 16x16 image in editor ARGB format', () {
      final source = img.Image(width: 16, height: 16, numChannels: 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          source.setPixelRgba(x, y, x * 16, y * 16, (x + y) * 8, 255);
        }
      }

      final result = ImageImportConverter.convertCroppedImage(
        img.encodePng(source),
      );

      expect(result.suggestedMode, ImageConversionMode.pixelArt);
      expect(result.pixelArtData, hasLength(16));
      expect(result.pixelArtData.every((row) => row.length == 16), isTrue);
      expect(result.pixelArtData[5][7], 0xFF705060);
      expect(result.pixelArtData[15][15], 0xFFF0F0F0);
    });

    test('reconstructs enlarged pixel art with dominant cell colors', () {
      final source = img.Image(width: 160, height: 160, numChannels: 4);
      for (var row = 0; row < 16; row++) {
        for (var column = 0; column < 16; column++) {
          final useCyan = (row + column).isEven;
          final red = useCyan ? 0 : 255;
          final green = useCyan ? 217 : 0;
          final blue = useCyan ? 255 : 110;
          for (var y = row * 10; y < row * 10 + 10; y++) {
            for (var x = column * 10; x < column * 10 + 10; x++) {
              source.setPixelRgba(x, y, red, green, blue, 255);
            }
          }
          source.setPixelRgba(column * 10, row * 10, 255, 0, 255, 255);
        }
      }

      final result = ImageImportConverter.convertCroppedImage(
        img.encodePng(source),
      );

      expect(result.suggestedMode, ImageConversionMode.pixelArt);
      expect(result.pixelArtData[4][9], 0xFFFF006E);
      expect(result.pixelArtData[12][4], 0xFF00D9FF);
    });

    test('photo conversion returns exactly 256 target pixels', () {
      final source = img.Image(width: 137, height: 137, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(
            x,
            y,
            x * 255 ~/ 136,
            y * 255 ~/ 136,
            (x * 13 + y * 7) % 256,
            255,
          );
        }
      }

      final result = ImageImportConverter.convertCroppedImage(
        img.encodePng(source),
      );

      expect(result.suggestedMode, ImageConversionMode.photo);
      expect(result.photoData, hasLength(16));
      expect(result.photoData.expand((row) => row), hasLength(256));
      expect(result.photoData.every((row) => row.length == 16), isTrue);
    });

    test('maps transparent pixels to off and composites partial alpha', () {
      final source = img.Image(width: 16, height: 16, numChannels: 4);
      source.clear(img.ColorRgba8(0, 255, 0, 255));
      source.setPixelRgba(0, 0, 255, 0, 0, 0);
      source.setPixelRgba(1, 0, 255, 0, 0, 16);
      source.setPixelRgba(2, 0, 255, 0, 0, 128);

      final result = ImageImportConverter.convertCroppedImage(
        img.encodePng(source),
      );

      expect(result.pixelArtData[0][0], 0);
      expect(result.pixelArtData[0][1], 0);
      expect(result.pixelArtData[0][2], 0xFF800000);
      expect(result.pixelArtData[0][3], 0xFF00FF00);
    });

    test('normalizes JPEG EXIF orientation before conversion', () {
      final source = img.Image(width: 16, height: 16, numChannels: 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          if (x < 8) {
            source.setPixelRgba(x, y, 255, 0, 0, 255);
          } else {
            source.setPixelRgba(x, y, 0, 0, 255, 255);
          }
        }
      }
      source.exif.imageIfd.orientation = 6;

      final result = ImageImportConverter.convertCroppedImage(
        img.encodeJpg(source, quality: 100),
      );

      final topLeft = result.pixelArtData[1][1];
      final bottomLeft = result.pixelArtData[14][1];
      expect((topLeft >> 16) & 0xFF, greaterThan(220));
      expect(topLeft & 0xFF, lessThan(30));
      expect((bottomLeft >> 16) & 0xFF, lessThan(30));
      expect(bottomLeft & 0xFF, greaterThan(220));
    });

    test('pixel-art fallback uses nearest neighbor without blended colors', () {
      final source = img.Image(width: 17, height: 17, numChannels: 4);
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 17; x++) {
          source.setPixelRgba(
            x,
            y,
            x < 8 ? 255 : 0,
            0,
            x < 8 ? 0 : 255,
            255,
          );
        }
      }

      final result = ImageImportConverter.convertCroppedImage(
        img.encodePng(source),
      );
      final colors = result.pixelArtData.expand((row) => row).toSet();

      expect(colors, {0xFFFF0000, 0xFF0000FF});
    });

    test('rejects non-square data instead of stretching it', () {
      final source = img.Image(width: 32, height: 16, numChannels: 4)
        ..clear(img.ColorRgb8(255, 0, 0));

      expect(
        () => ImageImportConverter.convertCroppedImage(img.encodePng(source)),
        throwsA(
          isA<ImageImportFailure>().having(
            (error) => error.message,
            'message',
            contains('not square'),
          ),
        ),
      );
    });
  });
}
