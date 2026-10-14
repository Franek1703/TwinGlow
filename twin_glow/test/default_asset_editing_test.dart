import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/features/asset_editor/cubit/asset_editor_cubit.dart';
import 'package:twin_glow/features/asset_editor/cubit/animation_editor_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

void main() {
  test(
    'image editor preserves Default across repeated saves and library reloads',
    () async {
      final repository = FirebaseFakeRepository();
      final template = (await repository.getDefaultAssets()).first;
      final cubit = AssetEditorCubit(
        repository,
        'user1',
        AssetType.image,
        asset: template,
      );
      addTearDown(cubit.close);
      cubit.updateName('Updated default');
      await cubit.save();
      expect(cubit.state.error, isNull);
      expect(cubit.state.asset!.isDefault, isTrue);
      cubit.updateName('Updated again');
      await cubit.save();
      expect(cubit.state.error, isNull);
      final saved = (await repository.getDefaultAssets()).singleWhere(
        (a) => a.id == template.id,
      );
      expect(saved.name, 'Updated again');
      expect(saved.isDefault, isTrue);
      expect(saved.revision, template.revision + 2);
      expect(
        (await repository.getUserAssets(
          'user1',
        )).any((a) => a.id == template.id),
        isFalse,
      );
    },
  );

  test('animation editor preserves Default across repeated saves', () async {
    final frames = List.generate(2, (_) {
      final pixels = AnimationFrameModel.emptyGrid();
      pixels[0][0] = 0xFFFF0000;
      return AnimationFrameModel(pixels: pixels, durationMs: 100);
    });
    final template = AssetModel(
      id: 'template-animation',
      name: 'Template',
      type: AssetType.animation,
      isDefault: true,
      frames: frames,
    );
    final repository = _RecordingRepository();
    final cubit = AnimationEditorCubit(repository, 'user1', asset: template);
    addTearDown(cubit.close);
    await cubit.save();
    await cubit.save();
    expect(cubit.state.error, isNull);
    expect(cubit.state.asset!.isDefault, isTrue);
    expect(repository.saved!.isDefault, isTrue);
    expect(cubit.state.asset!.revision, 2);
  });
}

class _RecordingRepository extends FirebaseFakeRepository {
  AssetModel? saved;
  @override
  Future<void> updateAsset(String id, AssetModel asset) async {
    saved = asset;
  }
}
