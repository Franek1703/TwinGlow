import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/codecs/animation_codec.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/features/asset_editor/cubit/animation_editor_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

/// Handing imported frames to the animation editor. The import is transient:
/// it seeds a new asset and never overrides one that was loaded.
void main() {
  List<AnimationFrameModel> importedFrames() => [
    AnimationFrameModel(
      pixels: List.generate(
        16,
        (row) => List.generate(16, (column) => 0xFF000000 | row << 8 | column),
      ),
      durationMs: 120,
    ),
    AnimationFrameModel(
      pixels: List.generate(16, (_) => List.filled(16, 0xFF00D9FF)),
      durationMs: 250,
    ),
  ];

  test('imported frames initialize a new asset and are deep-copied', () {
    final imported = importedFrames();
    final cubit = AnimationEditorCubit(
      FirebaseFakeRepository(),
      'user1',
      initialFrames: imported,
    );
    addTearDown(cubit.close);

    expect(cubit.isNewAsset, isTrue);
    expect(cubit.state.frames, hasLength(2));
    expect(cubit.state.frames[0].durationMs, 120);
    expect(cubit.state.frames[1].durationMs, 250);
    expect(cubit.state.frames[1].pixels[0][0], 0xFF00D9FF);

    imported[0].pixels[0][0] = 0x12345678;
    expect(cubit.state.frames[0].pixels[0][0], isNot(0x12345678));
  });

  test('an existing asset takes precedence over imported frames', () {
    final asset = AssetModel(
      id: 'anim1',
      name: 'Saved',
      type: AssetType.animation,
      frames: [
        AnimationFrameModel(
          pixels: List.generate(16, (_) => List.filled(16, 0xFFFF006E)),
          durationMs: 400,
        ),
        AnimationFrameModel(
          pixels: List.generate(16, (_) => List.filled(16, 0xFF39FF14)),
          durationMs: 400,
        ),
      ],
    );

    final cubit = AnimationEditorCubit(
      FirebaseFakeRepository(),
      'user1',
      asset: asset,
      initialFrames: importedFrames(),
    );
    addTearDown(cubit.close);

    expect(cubit.isNewAsset, isFalse);
    expect(cubit.state.frames[0].pixels[0][0], 0xFFFF006E);
    expect(cubit.state.frames[0].durationMs, 400);
    expect(cubit.state.name, 'Saved');
  });

  test(
    'imported animations stay editable and save through createAsset',
    () async {
      final repository = FirebaseFakeRepository();
      final cubit = AnimationEditorCubit(
        repository,
        'user1',
        initialFrames: importedFrames(),
      );
      addTearDown(cubit.close);

      cubit.addFrame();
      cubit.setFrameDuration(600);
      cubit.updateName('Imported loop');
      await cubit.save();

      final saved = (await repository.getUserAssets(
        'user1',
      )).singleWhere((asset) => asset.name == 'Imported loop');

      expect(cubit.state.error, isNull);
      expect(saved.type, AssetType.animation);
      expect(saved.frames, hasLength(3));
      expect(saved.frames![0].durationMs, 120);
      expect(saved.pixelData, cubit.state.frames.first.pixels);
    },
  );

  test('a too-short import falls back to the manual blank timeline', () {
    final cubit = AnimationEditorCubit(
      FirebaseFakeRepository(),
      'user1',
      initialFrames: [
        AnimationFrameModel(
          pixels: List.generate(16, (_) => List.filled(16, 0xFFFF0000)),
          durationMs: 100,
        ),
      ],
    );
    addTearDown(cubit.close);

    expect(cubit.state.frames, hasLength(AnimationCodec.minFrames));
    expect(cubit.state.frames.every((frame) => !frame.hasVisiblePixel), isTrue);
  });

  test('manual creation still starts on two blank 200ms frames', () {
    final cubit = AnimationEditorCubit(FirebaseFakeRepository(), 'user1');
    addTearDown(cubit.close);

    expect(cubit.state.frames, hasLength(2));
    expect(
      cubit.state.frames.every(
        (frame) =>
            frame.durationMs == AnimationFrameModel.defaultDurationMs &&
            !frame.hasVisiblePixel,
      ),
      isTrue,
    );
  });
}
