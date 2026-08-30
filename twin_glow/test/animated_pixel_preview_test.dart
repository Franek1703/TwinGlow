import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/widgets/animated_pixel_preview.dart';
import 'package:twin_glow/core/widgets/pixel_preview.dart';

List<List<int>> gridWith(Map<int, int> lit) {
  final grid = AnimationFrameModel.emptyGrid();
  lit.forEach((index, rgb) => grid[index ~/ 16][index % 16] = 0xFF000000 | rgb);
  return grid;
}

/// The colour the preview is currently showing at pixel 0.
int shownPixel(WidgetTester tester) {
  return tester.widget<PixelPreview>(find.byType(PixelPreview)).data[0][0];
}

Future<void> pumpPreview(
  WidgetTester tester,
  Widget preview,
) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 200, height: 200, child: preview),
        ),
      ),
    ),
  );
}

void main() {
  final threeFrames = [
    AnimationFrameModel(pixels: gridWith({0: 0xFF0000}), durationMs: 100),
    AnimationFrameModel(pixels: gridWith({0: 0x00FF00}), durationMs: 200),
    AnimationFrameModel(pixels: gridWith({0: 0x0000FF}), durationMs: 300),
  ];

  testWidgets('frame 0 is on screen immediately', (tester) async {
    await pumpPreview(tester, AnimatedPixelPreview(frames: threeFrames));

    expect(shownPixel(tester), 0xFFFF0000);
  });

  testWidgets('each frame stays visible for its own duration', (tester) async {
    await pumpPreview(tester, AnimatedPixelPreview(frames: threeFrames));

    // Frame 0 holds for its full 100ms.
    await tester.pump(const Duration(milliseconds: 99));
    expect(shownPixel(tester), 0xFFFF0000);

    await tester.pump(const Duration(milliseconds: 1));
    expect(shownPixel(tester), 0xFF00FF00);

    // Frame 1 holds for 200ms, not 100.
    await tester.pump(const Duration(milliseconds: 199));
    expect(shownPixel(tester), 0xFF00FF00);

    await tester.pump(const Duration(milliseconds: 1));
    expect(shownPixel(tester), 0xFF0000FF);
  });

  testWidgets('the last frame returns to frame 0', (tester) async {
    await pumpPreview(tester, AnimatedPixelPreview(frames: threeFrames));

    await tester.pump(const Duration(milliseconds: 100)); // -> frame 1
    await tester.pump(const Duration(milliseconds: 200)); // -> frame 2
    expect(shownPixel(tester), 0xFF0000FF);

    await tester.pump(const Duration(milliseconds: 300)); // -> loops to frame 0
    expect(shownPixel(tester), 0xFFFF0000);

    // And keeps going round.
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownPixel(tester), 0xFF00FF00);
  });

  testWidgets('a paused preview holds the frame being edited', (tester) async {
    await pumpPreview(
      tester,
      AnimatedPixelPreview(
        frames: threeFrames,
        isPlaying: false,
        pausedFrameIndex: 2,
      ),
    );

    expect(shownPixel(tester), 0xFF0000FF);

    // Time passing changes nothing while paused.
    await tester.pump(const Duration(seconds: 2));
    expect(shownPixel(tester), 0xFF0000FF);
  });

  testWidgets('pausing stops advancing and resuming continues', (tester) async {
    await pumpPreview(
      tester,
      AnimatedPixelPreview(frames: threeFrames, isPlaying: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownPixel(tester), 0xFF00FF00);

    await pumpPreview(
      tester,
      AnimatedPixelPreview(
        frames: threeFrames,
        isPlaying: false,
        pausedFrameIndex: 1,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(shownPixel(tester), 0xFF00FF00);
  });

  testWidgets('restarting returns to frame 0', (tester) async {
    await pumpPreview(
      tester,
      const AnimatedPixelPreview(frames: [], restartToken: 0),
    );

    await pumpPreview(
      tester,
      AnimatedPixelPreview(frames: threeFrames, restartToken: 0),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownPixel(tester), 0xFF00FF00);

    await pumpPreview(
      tester,
      AnimatedPixelPreview(frames: threeFrames, restartToken: 1),
    );
    expect(shownPixel(tester), 0xFFFF0000);
  });

  testWidgets('replacing the asset restarts at frame 0', (tester) async {
    await pumpPreview(tester, AnimatedPixelPreview(frames: threeFrames));
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownPixel(tester), 0xFF00FF00);

    final other = [
      AnimationFrameModel(pixels: gridWith({0: 0xABCDEF}), durationMs: 100),
      AnimationFrameModel(pixels: gridWith({0: 0x123456}), durationMs: 100),
    ];
    await pumpPreview(tester, AnimatedPixelPreview(frames: other));

    expect(shownPixel(tester), 0xFFABCDEF);
  });

  testWidgets('an empty frame list renders a blank grid, not an error',
      (tester) async {
    await pumpPreview(tester, const AnimatedPixelPreview(frames: []));

    expect(shownPixel(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single frame never schedules a timer', (tester) async {
    await pumpPreview(
      tester,
      AnimatedPixelPreview(frames: [threeFrames.first]),
    );

    await tester.pump(const Duration(seconds: 5));
    expect(shownPixel(tester), 0xFFFF0000);
    expect(tester.takeException(), isNull);
  });

  test('a library thumbnail uses the first frame', () {
    final asset = AssetModel(
      id: 'a1',
      name: 'Blink',
      type: AssetType.animation,
      frames: threeFrames,
    );

    expect(asset.previewPixelData![0][0], 0xFFFF0000);
  });

  test('an image thumbnail still uses its own grid', () {
    final asset = AssetModel(
      id: 'i1',
      name: 'Heart',
      type: AssetType.image,
      pixelData: gridWith({0: 0x00FF00}),
    );

    expect(asset.previewPixelData![0][0], 0xFF00FF00);
  });
}
