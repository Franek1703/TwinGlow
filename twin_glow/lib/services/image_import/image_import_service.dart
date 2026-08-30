import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_colors.dart';
import 'image_import_converter.dart';

enum ImageImportSource { photoLibrary, files }

class SelectedImportImage {
  final String path;
  final String name;

  const SelectedImportImage({required this.path, required this.name});
}

abstract class ImageImportService {
  Future<SelectedImportImage?> selectImage(ImageImportSource source);

  Future<String?> cropToSquare(String sourcePath);

  Future<ImageConversionResult> convertCroppedImage(String croppedPath);
}

class LocalImageImportService implements ImageImportService {
  static const int _maxFileBytes = 50 * 1024 * 1024;

  final ImagePicker _imagePicker;
  final ImageCropper _imageCropper;

  LocalImageImportService({
    ImagePicker? imagePicker,
    ImageCropper? imageCropper,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _imageCropper = imageCropper ?? ImageCropper();

  @override
  Future<SelectedImportImage?> selectImage(ImageImportSource source) async {
    try {
      final selected = switch (source) {
        ImageImportSource.photoLibrary => await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 4096,
          maxHeight: 4096,
        ),
        ImageImportSource.files => await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Images',
              extensions: ['png', 'jpg', 'jpeg', 'webp'],
              mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
              uniformTypeIdentifiers: [
                'public.png',
                'public.jpeg',
                'org.webmproject.webp',
              ],
            ),
          ],
        ),
      };
      if (selected == null) return null;

      final file = File(selected.path);
      final length = await file.length();
      if (length <= 0) {
        throw const ImageImportFailure('The selected image is empty.');
      }
      if (length > _maxFileBytes) {
        throw const ImageImportFailure(
          'This image is too large. Choose a file smaller than 50 MB.',
        );
      }

      final bytes = await file.readAsBytes();
      await Isolate.run(() => ImageImportConverter.inspectSource(bytes));
      return SelectedImportImage(path: selected.path, name: selected.name);
    } on ImageImportFailure {
      rethrow;
    } on PlatformException catch (error) {
      throw ImageImportFailure(_platformMessage(error));
    } on FileSystemException {
      throw const ImageImportFailure(
        'TwinGlow could not read the selected image. Please choose it again.',
      );
    } catch (_) {
      throw const ImageImportFailure(
        'TwinGlow could not open this image. Please choose another one.',
      );
    }
  }

  @override
  Future<String?> cropToSquare(String sourcePath) async {
    try {
      final cropped = await _imageCropper.cropImage(
        sourcePath: sourcePath,
        maxWidth: 2048,
        maxHeight: 2048,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.png,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: AppColors.bgSecondary,
            toolbarWidgetColor: AppColors.textPrimary,
            activeControlsWidgetColor: AppColors.accentCyan,
            cropFrameColor: AppColors.accentCyan,
            cropGridColor: AppColors.textPrimary,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.square,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'Crop Image',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
        ],
      );
      return cropped?.path;
    } on PlatformException catch (error) {
      throw ImageImportFailure(_platformMessage(error));
    } catch (_) {
      throw const ImageImportFailure(
        'TwinGlow could not crop this image. Please try again.',
      );
    }
  }

  @override
  Future<ImageConversionResult> convertCroppedImage(String croppedPath) async {
    try {
      final bytes = await File(croppedPath).readAsBytes();
      return await Isolate.run(
        () => ImageImportConverter.convertCroppedImage(bytes),
      );
    } on ImageImportFailure {
      rethrow;
    } on FileSystemException {
      throw const ImageImportFailure(
        'TwinGlow could not read the cropped image. Please crop it again.',
      );
    } catch (_) {
      throw const ImageImportFailure(
        'TwinGlow could not convert this image. Please try another image.',
      );
    }
  }

  String _platformMessage(PlatformException error) {
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    if (code.contains('permission') ||
        code.contains('denied') ||
        message.contains('permission') ||
        message.contains('denied')) {
      return 'Photo access is unavailable. Allow access in your device settings and try again.';
    }
    return 'TwinGlow could not open the image picker. Please try again.';
  }
}
