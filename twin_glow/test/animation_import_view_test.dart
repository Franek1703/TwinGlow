import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/services/animation_import/animation_crop.dart';
import 'package:twin_glow/services/animation_import/animation_frame_timeline.dart';
import 'package:twin_glow/services/animation_import/animation_import_converter.dart';
import 'package:twin_glow/services/animation_import/animation_import_service.dart';
import 'package:twin_glow/services/image_import/editor_image_converter.dart';
import 'package:twin_glow/services/image_import/image_import_service.dart';
import 'package:twin_glow/views/animation_import/animation_crop_view.dart';
import 'package:twin_glow/views/animation_import/import_animation_view.dart';

/// The screen wiring: picking a source opens the crop screen, finishing it
/// converts, and Use Animation hands frames to the editor route.
/// `pumpAndSettle` is useless on this screen: the progress spinner and the
/// converted preview both animate forever, so the frame queue never empties.
/// Pumping a bounded span covers the route transitions and async gaps instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  Future<void> pumpImporter(
    WidgetTester tester,
    AnimationImportService service, {
    List<AnimationFrameModel>? capturedFrames,
    VoidCallback? onEditorOpened,
  }) async {
    // The importer is designed against a phone; matching the design size keeps
    // ScreenUtil at 1:1 so unrelated layout scaling cannot mask the wiring.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/assets',
      routes: [
        GoRoute(
          path: '/assets',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/asset/import/animation'),
                child: const Text('Open importer'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/asset/import/animation',
          builder: (context, state) => ImportAnimationView(service: service),
        ),
        GoRoute(
          path: '/asset/create/animation',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is List<AnimationFrameModel>) {
              capturedFrames?.addAll(extra);
            }
            onEditorOpened?.call();
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Close editor'),
                ),
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (context, _) => MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Open importer'));
    await settle(tester);
  }

  testWidgets('the crop screen opens, converts, and previews the animation', (
    tester,
  ) async {
    await pumpImporter(tester, _FakeAnimationImportService());

    await tester.tap(find.text('Files'));
    await settle(tester);

    expect(find.byType(AnimationCropView), findsOneWidget);

    await tester.tap(find.byKey(const Key('animation_crop_done')));
    await settle(tester);

    expect(find.byType(AnimationCropView), findsNothing);
    expect(find.text('Use Animation'), findsOneWidget);
    expect(find.text('3 source frames → 2 imported · 0.20s'), findsOneWidget);
    expect(find.text('Pixel Art'), findsOneWidget);
    expect(find.text('Suggested'), findsOneWidget);
  });

  testWidgets('Use Animation hands deep-copied frames to the editor route', (
    tester,
  ) async {
    final captured = <AnimationFrameModel>[];
    final service = _FakeAnimationImportService();
    await pumpImporter(tester, service, capturedFrames: captured);

    await tester.tap(find.text('Files'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('animation_crop_done')));
    await settle(tester);
    // The preview page scrolls; the action sits below the fold on a phone.
    await tester.ensureVisible(find.text('Use Animation'));
    await settle(tester);
    await tester.tap(find.text('Use Animation'));
    await settle(tester);

    expect(find.text('Close editor'), findsOneWidget);
    expect(captured, hasLength(2));
    expect(captured.first.pixels[0][0], 0xFFFF0000);
    expect(
      captured.first.pixels,
      isNot(same(service.lastResult!.pixelArt.frames.first.pixels)),
    );
  });

  testWidgets('cancelling the first crop leaves the importer', (tester) async {
    var editorOpened = false;
    await pumpImporter(
      tester,
      _FakeAnimationImportService(),
      onEditorOpened: () => editorOpened = true,
    );

    await tester.tap(find.text('Files'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('animation_crop_cancel')));
    await settle(tester);

    expect(find.byType(ImportAnimationView), findsNothing);
    expect(editorOpened, isFalse);
  });

  testWidgets('a rejected file offers another try', (tester) async {
    await pumpImporter(
      tester,
      _FakeAnimationImportService(
        selectionFailure: const ImageImportFailure(
          'This file holds a single frame.',
        ),
      ),
    );

    await tester.tap(find.text('Files'));
    await settle(tester);

    expect(find.text('Animation import failed'), findsOneWidget);
    expect(find.text('This file holds a single frame.'), findsOneWidget);
    expect(find.text('Choose Another File'), findsOneWidget);
  });
}

class _FakeAnimationImportService implements AnimationImportService {
  final ImageImportFailure? selectionFailure;

  AnimationConversionResult? lastResult;

  _FakeAnimationImportService({this.selectionFailure});

  @override
  Future<SelectedImportAnimation?> selectAnimation(
    ImageImportSource source,
  ) async {
    if (selectionFailure != null) throw selectionFailure!;
    return const SelectedImportAnimation(path: 'loop.gif', name: 'loop.gif');
  }

  @override
  Future<AnimationPreviewSource> loadPreview(String path) async {
    final still = img.Image(width: 32, height: 32, numChannels: 4);
    img.fill(still, color: img.ColorRgba8(255, 0, 0, 255));
    return AnimationPreviewSource(
      previewPng: Uint8List.fromList(img.encodePng(still)),
      sourceWidth: 32,
      sourceHeight: 32,
      sourceFrameCount: 3,
    );
  }

  @override
  Future<AnimationConversionResult> convert(
    String path,
    NormalizedCrop crop,
  ) async {
    return lastResult = AnimationConversionResult(
      pixelArt: _timeline(0xFFFF0000),
      photo: _timeline(0xFF0000FF),
      suggestedMode: ImageConversionMode.pixelArt,
      sourceWidth: 32,
      sourceHeight: 32,
      cropSize: 32,
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
