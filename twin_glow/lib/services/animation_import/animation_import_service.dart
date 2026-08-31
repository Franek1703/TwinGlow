import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../image_import/editor_image_converter.dart';
import '../image_import/image_import_service.dart';
import 'animation_crop.dart';
import 'animation_import_converter.dart';

class SelectedImportAnimation {
  final String path;
  final String name;

  const SelectedImportAnimation({required this.path, required this.name});
}

abstract class AnimationImportService {
  Future<SelectedImportAnimation?> selectAnimation(ImageImportSource source);

  Future<AnimationPreviewSource> loadPreview(String path);

  Future<AnimationConversionResult> convert(String path, NormalizedCrop crop);
}

class LocalAnimationImportService implements AnimationImportService {
  final ImagePicker _imagePicker;

  LocalAnimationImportService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  @override
  Future<SelectedImportAnimation?> selectAnimation(
    ImageImportSource source,
  ) async {
    try {
      final selected = switch (source) {
        // No maxWidth/maxHeight and no quality conversion: asking the picker
        // to resize makes it re-encode, and a re-encoded animation comes back
        // as a single flattened frame.
        ImageImportSource.photoLibrary => await _imagePicker.pickImage(
          source: ImageSource.gallery,
        ),
        ImageImportSource.files => await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Animations',
              extensions: ['gif', 'webp', 'png', 'apng'],
              mimeTypes: ['image/gif', 'image/webp', 'image/png'],
              uniformTypeIdentifiers: [
                'com.compuserve.gif',
                'org.webmproject.webp',
                'public.png',
              ],
            ),
          ],
        ),
      };
      if (selected == null) return null;

      final file = File(selected.path);
      final length = await file.length();
      if (length <= 0) {
        throw const ImageImportFailure('The selected file is empty.');
      }
      if (length > AnimationImportConverter.maxFileBytes) {
        throw const ImageImportFailure(
          'This file is too large. Choose one smaller than 50 MB.',
        );
      }

      // Header-only check, so an unusable pick fails here rather than after
      // the user has already framed a crop.
      final bytes = await file.readAsBytes();
      await Isolate.run(() => AnimationImportConverter.inspectSource(bytes));
      return SelectedImportAnimation(path: selected.path, name: selected.name);
    } on ImageImportFailure {
      rethrow;
    } on PlatformException catch (error) {
      throw ImageImportFailure(_platformMessage(error));
    } on FileSystemException {
      throw const ImageImportFailure(
        'TwinGlow could not read the selected file. Please choose it again.',
      );
    } catch (_) {
      throw const ImageImportFailure(
        'TwinGlow could not open this file. Please choose another one.',
      );
    }
  }

  @override
  Future<AnimationPreviewSource> loadPreview(String path) async {
    final bytes = await _read(path);
    try {
      return await Isolate.run(
        () => AnimationImportConverter.loadPreview(bytes),
      );
    } on ImageImportFailure {
      rethrow;
    } catch (_) {
      throw const ImageImportFailure(
        'TwinGlow could not read this animation. Please choose another one.',
      );
    }
  }

  @override
  Future<AnimationConversionResult> convert(
    String path,
    NormalizedCrop crop,
  ) async {
    final bytes = await _read(path);
    try {
      return await Isolate.run(
        () => AnimationImportConverter.convert(bytes, crop),
      );
    } on ImageImportFailure {
      rethrow;
    } catch (_) {
      throw const ImageImportFailure(
        'TwinGlow could not convert this animation. Please try another one.',
      );
    }
  }

  Future<Uint8List> _read(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      throw const ImageImportFailure(
        'TwinGlow could not read the selected file. Please choose it again.',
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
    return 'TwinGlow could not open the picker. Please try again.';
  }
}
