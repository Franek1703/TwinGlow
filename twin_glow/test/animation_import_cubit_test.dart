import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/features/animation_import/cubit/animation_import_cubit.dart';
import 'package:twin_glow/services/animation_import/animation_crop.dart';
import 'package:twin_glow/services/animation_import/animation_frame_timeline.dart';
import 'package:twin_glow/services/animation_import/animation_import_converter.dart';
import 'package:twin_glow/services/animation_import/animation_import_service.dart';
import 'package:twin_glow/services/image_import/editor_image_converter.dart';
import 'package:twin_glow/services/image_import/image_import_service.dart';

void main() {
  test('selection loads a preview and waits for the crop screen', () async {
    final service = _FakeAnimationImportService();
    final cubit = AnimationImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);

    expect(cubit.state.status, AnimationImportStatus.awaitingCrop);
    expect(cubit.state.selection!.name, 'loop.gif');
    expect(cubit.state.preview!.sourceWidth, 48);
    // Opens on the largest centred square, so a wide source is framed sanely.
    expect(cubit.state.crop!.toRect(48, 16), (x: 16, y: 0, size: 16));
    expect(service.convertedCrops, isEmpty);
  });

  test('applying a crop converts and adopts the suggested mode', () async {
    final service = _FakeAnimationImportService();
    final cubit = AnimationImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);
    await cubit.applyCrop(const NormalizedCrop(left: 0, top: 0, size: 0.25));

    expect(cubit.state.status, AnimationImportStatus.ready);
    expect(cubit.state.mode, ImageConversionMode.pixelArt);
    expect(cubit.state.frames!.first.pixels[0][0], 0xFFFF0000);
    expect(service.convertedCrops.single.size, 0.25);
  });

  test('mode changes choose the matching precomputed timeline', () async {
    final cubit = AnimationImportCubit(_FakeAnimationImportService());
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);
    await cubit.applyCrop(const NormalizedCrop(left: 0, top: 0, size: 1));
    expect(cubit.state.frames!.first.pixels[0][0], 0xFFFF0000);

    cubit.setMode(ImageConversionMode.photo);

    expect(cubit.state.frames!.first.pixels[0][0], 0xFF0000FF);
  });

  test('picker cancellation ends cleanly without decoding', () async {
    final service = _FakeAnimationImportService(selection: null);
    final cubit = AnimationImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.photoLibrary);

    expect(cubit.state.status, AnimationImportStatus.cancelled);
    expect(service.previewedPaths, isEmpty);
  });

  test('backing out of the first crop ends the import', () async {
    final cubit = AnimationImportCubit(_FakeAnimationImportService());
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);
    cubit.cancelCrop();

    expect(cubit.state.status, AnimationImportStatus.cancelled);
  });

  test('backing out of a recrop keeps the preview already on screen', () async {
    final cubit = AnimationImportCubit(_FakeAnimationImportService());
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);
    await cubit.applyCrop(const NormalizedCrop(left: 0, top: 0, size: 1));
    final kept = cubit.state.conversion;

    cubit.changeCrop();
    expect(cubit.state.status, AnimationImportStatus.awaitingCrop);

    cubit.cancelCrop();

    expect(cubit.state.status, AnimationImportStatus.ready);
    expect(cubit.state.conversion, same(kept));
  });

  test(
    'a failed recrop keeps the previous preview and reports the reason',
    () async {
      final service = _FakeAnimationImportService();
      final cubit = AnimationImportCubit(service);
      addTearDown(cubit.close);

      await cubit.start(ImageImportSource.files);
      await cubit.applyCrop(const NormalizedCrop(left: 0, top: 0, size: 1));
      final kept = cubit.state.conversion;

      service.failNextConversion = true;
      cubit.changeCrop();
      await cubit.applyCrop(const NormalizedCrop(left: 0.5, top: 0, size: 0.2));

      expect(cubit.state.status, AnimationImportStatus.ready);
      expect(cubit.state.conversion, same(kept));
      expect(cubit.state.error, contains('too long'));
    },
  );

  test('a failed first conversion is a recoverable failure screen', () async {
    final service = _FakeAnimationImportService()..failNextConversion = true;
    final cubit = AnimationImportCubit(service);
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.files);
    await cubit.applyCrop(const NormalizedCrop(left: 0, top: 0, size: 1));

    expect(cubit.state.status, AnimationImportStatus.failure);
    expect(cubit.state.conversion, isNull);
    expect(cubit.state.error, isNotNull);
  });

  test('a rejected selection surfaces the decoder message', () async {
    final cubit = AnimationImportCubit(
      _FakeAnimationImportService(
        selectionFailure: const ImageImportFailure(
          'This file holds a single frame.',
        ),
      ),
    );
    addTearDown(cubit.close);

    await cubit.start(ImageImportSource.photoLibrary);

    expect(cubit.state.status, AnimationImportStatus.failure);
    expect(cubit.state.error, 'This file holds a single frame.');
  });
}

class _FakeAnimationImportService implements AnimationImportService {
  final SelectedImportAnimation? selection;
  final ImageImportFailure? selectionFailure;

  bool failNextConversion = false;
  final List<String> previewedPaths = [];
  final List<NormalizedCrop> convertedCrops = [];

  _FakeAnimationImportService({
    this.selection = const SelectedImportAnimation(
      path: 'loop.gif',
      name: 'loop.gif',
    ),
    this.selectionFailure,
  });

  @override
  Future<SelectedImportAnimation?> selectAnimation(
    ImageImportSource source,
  ) async {
    if (selectionFailure != null) throw selectionFailure!;
    return selection;
  }

  @override
  Future<AnimationPreviewSource> loadPreview(String path) async {
    previewedPaths.add(path);
    return AnimationPreviewSource(
      previewPng: Uint8List(0),
      sourceWidth: 48,
      sourceHeight: 16,
      sourceFrameCount: 3,
    );
  }

  @override
  Future<AnimationConversionResult> convert(
    String path,
    NormalizedCrop crop,
  ) async {
    if (failNextConversion) {
      failNextConversion = false;
      throw const ImageImportFailure(
        'This animation is too long or changes too much between frames.',
      );
    }
    convertedCrops.add(crop);
    return AnimationConversionResult(
      pixelArt: _timeline(0xFFFF0000),
      photo: _timeline(0xFF0000FF),
      suggestedMode: ImageConversionMode.pixelArt,
      sourceWidth: 48,
      sourceHeight: 16,
      cropSize: 16,
    );
  }

  OptimizedTimeline _timeline(int color) {
    return OptimizedTimeline(
      frames: [
        AnimationFrameModel(
          pixels: List.generate(16, (_) => List.filled(16, color)),
          durationMs: 100,
        ),
        AnimationFrameModel(
          pixels: List.generate(16, (_) => List.filled(16, color ^ 0xFFFFFF)),
          durationMs: 100,
        ),
      ],
      sourceFrameCount: 3,
      totalDurationMs: 200,
      sourceDurationMs: 300,
    );
  }
}
