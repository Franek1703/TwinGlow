import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/codecs/animation_codec.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/user_model.dart';
import 'package:twin_glow/features/asset_editor/cubit/animation_editor_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

List<List<int>> gridWith(Map<int, int> lit) {
  final grid = AnimationFrameModel.emptyGrid();
  lit.forEach((index, rgb) => grid[index ~/ 16][index % 16] = 0xFF000000 | rgb);
  return grid;
}

AnimationEditorCubit newCubit({
  FirebaseFakeRepository? repository,
  AssetModel? asset,
}) {
  return AnimationEditorCubit(
    repository ?? _RecordingRepository(),
    'user1',
    asset: asset,
  );
}

void main() {
  test('a new animation starts on two blank 200ms frames', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    expect(cubit.state.frameCount, 2);
    expect(cubit.state.selectedFrameIndex, 0);
    for (final frame in cubit.state.frames) {
      expect(frame.durationMs, 200);
      expect(frame.hasVisiblePixel, isFalse);
    }
  });

  test('duplicating a frame produces an independent copy', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.updatePixelData(gridWith({0: 0xFF0000}));
    cubit.duplicateFrame(0);

    expect(cubit.state.frameCount, 3);
    expect(cubit.state.selectedFrameIndex, 1);
    expect(cubit.state.frames[1].pixels[0][0], 0xFFFF0000);

    // Editing the copy must not write through to the frame it came from.
    cubit.updatePixelData(gridWith({0: 0x00FF00}));
    expect(cubit.state.frames[1].pixels[0][0], 0xFF00FF00);
    expect(cubit.state.frames[0].pixels[0][0], 0xFFFF0000);
  });

  test('adding a frame inserts a blank after the selection and selects it', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.updatePixelData(gridWith({0: 0xFF0000}));
    cubit.addFrame();

    expect(cubit.state.frameCount, 3);
    expect(cubit.state.selectedFrameIndex, 1);
    expect(cubit.state.frames[1].hasVisiblePixel, isFalse);
    expect(cubit.state.frames[0].pixels[0][0], 0xFFFF0000);
  });

  test('the two-frame minimum blocks the last deletion', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    expect(cubit.state.canDeleteFrame, isFalse);
    cubit.deleteFrame(0);
    expect(cubit.state.frameCount, 2);

    cubit.addFrame();
    expect(cubit.state.canDeleteFrame, isTrue);
    cubit.deleteFrame(0);
    expect(cubit.state.frameCount, 2);
    expect(cubit.state.canDeleteFrame, isFalse);
  });

  test('the frame ceiling blocks further additions', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    while (cubit.state.canAddFrame) {
      cubit.addFrame();
    }
    expect(cubit.state.frameCount, AnimationCodec.maxFrames);

    cubit.addFrame();
    cubit.duplicateFrame(0);
    expect(cubit.state.frameCount, AnimationCodec.maxFrames);
  });

  test('deleting before the selection keeps the same frame selected', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.addFrame(); // 3 frames, selected 1
    cubit.selectFrame(2);
    cubit.updatePixelData(gridWith({7: 0xABCDEF}));

    cubit.deleteFrame(0);

    expect(cubit.state.frameCount, 2);
    expect(cubit.state.selectedFrameIndex, 1);
    expect(cubit.state.frames[1].pixels[0][7], 0xFFABCDEF);
  });

  test('reordering moves the frame and keeps the selection on it', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.updatePixelData(gridWith({0: 0xFF0000})); // frame 0
    cubit.addFrame();
    cubit.updatePixelData(gridWith({1: 0x00FF00})); // frame 1
    cubit.selectFrame(0);

    // ReorderableListView reports the insertion point in the pre-removal list.
    cubit.reorderFrames(0, 2);

    expect(cubit.state.frames[0].pixels[0][1], 0xFF00FF00);
    expect(cubit.state.frames[1].pixels[0][0], 0xFFFF0000);
    expect(cubit.state.selectedFrameIndex, 1);
  });

  test('selecting a frame bumps gridRevision so the canvas reloads', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    final before = cubit.state.gridRevision;
    cubit.selectFrame(1);
    expect(cubit.state.gridRevision, greaterThan(before));

    // Re-selecting the same frame is a no-op.
    final after = cubit.state.gridRevision;
    cubit.selectFrame(1);
    expect(cubit.state.gridRevision, after);
  });

  test('tools apply to the selected frame only', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.updatePixelData(gridWith({0: 0xFF0000}));
    cubit.selectFrame(1);
    cubit.updatePixelData(gridWith({0: 0x00FF00}));

    cubit.mirrorX();
    expect(cubit.state.frames[1].pixels[0][15], 0xFF00FF00);
    expect(cubit.state.frames[1].pixels[0][0], 0);
    // Frame 0 is untouched.
    expect(cubit.state.frames[0].pixels[0][0], 0xFFFF0000);

    cubit.clearGrid();
    expect(cubit.state.frames[1].hasVisiblePixel, isFalse);
    expect(cubit.state.frames[0].hasVisiblePixel, isTrue);
  });

  test('duration applies per frame and reports out-of-range values', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.setFrameDuration(1000);
    expect(cubit.state.frames[0].durationMs, 1000);
    expect(cubit.state.frames[1].durationMs, 200);
    expect(cubit.durationError, isNull);

    cubit.setFrameDuration(10);
    expect(cubit.durationError, contains('between'));

    cubit.setFrameDuration(6000);
    expect(cubit.durationError, isNotNull);
  });

  test('an over-limit payload fails the save with an editor message', () async {
    final repository = _RecordingRepository();
    final cubit = newCubit(repository: repository);
    addTearDown(cubit.close);

    cubit.updateName('Too big');
    while (cubit.state.canAddFrame) {
      cubit.addFrame();
    }
    // Every frame fully lit in an alternating colour: every pixel changes on
    // every transition, which no packing can fit.
    for (var i = 0; i < cubit.state.frameCount; i++) {
      cubit.selectFrame(i);
      cubit.updatePixelData(
        gridWith({for (var p = 0; p < 256; p++) p: i.isEven ? 0xFF0000 : 0x00FF00}),
      );
    }

    await cubit.save();

    expect(cubit.state.error, contains('character limit'));
    expect(repository.createdAsset, isNull);
    // Nothing was thrown away.
    expect(cubit.state.frameCount, AnimationCodec.maxFrames);
  });

  test('a blank animation is refused rather than saved', () async {
    final repository = _RecordingRepository();
    final cubit = newCubit(repository: repository);
    addTearDown(cubit.close);

    cubit.updateName('Nothing');
    await cubit.save();

    expect(cubit.state.error, contains('visible pixel'));
    expect(repository.createdAsset, isNull);
  });

  test('a missing name is refused before anything is encoded', () async {
    final repository = _RecordingRepository();
    final cubit = newCubit(repository: repository);
    addTearDown(cubit.close);

    await cubit.save();
    expect(cubit.state.error, 'Name is required');

    cubit.updateName('Blink');
    expect(cubit.state.error, isNull);
  });

  test('a failed save keeps every edit for the retry', () async {
    final repository = _FailingOnceRepository();
    final cubit = newCubit(repository: repository);
    addTearDown(cubit.close);

    cubit.updateName('Blink');
    cubit.updatePixelData(gridWith({3: 0xFF0000}));
    cubit.setFrameDuration(350);
    cubit.selectFrame(1);
    cubit.updatePixelData(gridWith({4: 0x00FF00}));

    await cubit.save();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.isLoading, isFalse);
    expect(repository.createdAsset, isNull);

    // The retry succeeds and carries the same frames.
    await cubit.save();
    expect(cubit.state.error, isNull);
    final saved = repository.createdAsset!;
    expect(saved.frames!.length, 2);
    expect(saved.frames![0].durationMs, 350);
    expect(saved.frames![0].pixels[0][3], 0xFFFF0000);
    expect(saved.frames![1].pixels[0][4], 0xFF00FF00);
    // pixelData carries the first frame for thumbnails.
    expect(saved.pixelData![0][3], 0xFFFF0000);
    expect(saved.type, AssetType.animation);
  });

  test('an existing animation opens on its saved frames', () {
    final cubit = newCubit(
      asset: AssetModel(
        id: 'a1',
        name: 'Blink',
        type: AssetType.animation,
        tags: const ['fun'],
        frames: [
          AnimationFrameModel(pixels: gridWith({0: 0xFF0000}), durationMs: 120),
          AnimationFrameModel(pixels: gridWith({1: 0x00FF00}), durationMs: 480),
          AnimationFrameModel(pixels: gridWith({2: 0x0000FF}), durationMs: 90),
        ],
      ),
    );
    addTearDown(cubit.close);

    expect(cubit.state.frameCount, 3);
    expect(cubit.state.name, 'Blink');
    expect(cubit.state.tags, ['fun']);
    expect(
      cubit.state.frames.map((f) => f.durationMs).toList(),
      [120, 480, 90],
    );

    // Editing the cubit must not mutate the asset it was opened from.
    cubit.clearGrid();
    expect(cubit.state.asset!.frames![0].pixels[0][0], 0xFFFF0000);
  });

  test('an animation stored as a single image opens padded to two frames', () {
    final cubit = newCubit(
      asset: AssetModel(
        id: 'a1',
        name: 'Half-made',
        type: AssetType.animation,
        pixelData: gridWith({0: 0xFF0000}),
      ),
    );
    addTearDown(cubit.close);

    expect(cubit.state.frameCount, 2);
    expect(cubit.state.frames[0].pixels[0][0], 0xFFFF0000);
    expect(cubit.state.frames[1].pixels[0][0], 0xFFFF0000);
  });

  test('an existing animation updates rather than creating a second asset',
      () async {
    final repository = _RecordingRepository();
    final cubit = newCubit(
      repository: repository,
      asset: AssetModel(
        id: 'existing',
        name: 'Blink',
        type: AssetType.animation,
        frames: [
          AnimationFrameModel(pixels: gridWith({0: 0xFF0000}), durationMs: 120),
          AnimationFrameModel(pixels: gridWith({1: 0x00FF00}), durationMs: 120),
        ],
      ),
    );
    addTearDown(cubit.close);

    await cubit.save();

    expect(repository.createdAsset, isNull);
    expect(repository.updatedAssetId, 'existing');
    expect(repository.updatedAsset?.frames?.length, 2);
  });

  test('playback toggles and restarts without disturbing the selection', () {
    final cubit = newCubit();
    addTearDown(cubit.close);

    cubit.selectFrame(1);
    expect(cubit.state.isPlaying, isFalse);

    cubit.togglePlayback();
    expect(cubit.state.isPlaying, isTrue);
    // Editing stays possible while the preview runs.
    expect(cubit.state.selectedFrameIndex, 1);

    cubit.togglePlayback();
    expect(cubit.state.isPlaying, isFalse);

    cubit.restartPlayback();
    expect(cubit.state.isPlaying, isTrue);
    expect(cubit.state.selectedFrameIndex, 1);
  });
}

class _RecordingRepository extends FirebaseFakeRepository {
  AssetModel? createdAsset;
  AssetModel? updatedAsset;
  String? updatedAssetId;

  @override
  Future<UserModel?> getCurrentUser() async => UserModel(
        id: 'user1',
        email: 'test@example.com',
        displayName: 'Test User',
      );

  @override
  Future<AssetModel> createAsset(String userId, AssetModel asset) async {
    createdAsset = asset;
    return asset;
  }

  @override
  Future<void> updateAsset(String assetId, AssetModel asset) async {
    updatedAssetId = assetId;
    updatedAsset = asset;
  }
}

class _FailingOnceRepository extends _RecordingRepository {
  bool _failed = false;

  @override
  Future<AssetModel> createAsset(String userId, AssetModel asset) async {
    if (!_failed) {
      _failed = true;
      throw Exception('network down');
    }
    return super.createAsset(userId, asset);
  }
}
