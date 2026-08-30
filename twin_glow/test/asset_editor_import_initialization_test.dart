import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/features/asset_editor/cubit/asset_editor_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

void main() {
  test('imported data initializes a new asset and uses the existing create flow',
      () async {
    final repository = FirebaseFakeRepository();
    final imported = List.generate(
      16,
      (row) => List.generate(16, (column) => 0xFF000000 | row << 8 | column),
    );
    final cubit = AssetEditorCubit(
      repository,
      'user1',
      AssetType.image,
      initialPixelData: imported,
    );
    addTearDown(cubit.close);

    expect(cubit.isNewAsset, isTrue);
    expect(cubit.state.pixelData, imported);
    imported[0][0] = 123;
    expect(cubit.state.pixelData[0][0], isNot(123));

    cubit.updateName('Imported image');
    await cubit.save();

    final saved = (await repository.getUserAssets('user1'))
        .singleWhere((asset) => asset.name == 'Imported image');
    expect(saved.type, AssetType.image);
    expect(saved.pixelData, cubit.state.pixelData);
  });

  test('manual creation still starts with the existing empty 16x16 grid', () {
    final cubit = AssetEditorCubit(
      FirebaseFakeRepository(),
      'user1',
      AssetType.image,
    );
    addTearDown(cubit.close);

    expect(cubit.isNewAsset, isTrue);
    expect(cubit.state.pixelData, hasLength(16));
    expect(cubit.state.pixelData.expand((row) => row), hasLength(256));
    expect(cubit.state.pixelData.expand((row) => row).every((pixel) => pixel == 0),
        isTrue);
  });
}
