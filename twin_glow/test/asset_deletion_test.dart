import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twin_glow/core/models/screen_asset_references.dart';
import 'package:twin_glow/core/models/user_model.dart';
import 'package:twin_glow/features/auth/cubit/auth_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/views/assets/assets_view.dart';

void main() {
  group('asset reference cleanup', () {
    test('promotes the next pooled asset when deleting the default', () {
      const references = ScreenAssetReferences(
        assetId: 'asset-a',
        defaultAssetId: 'asset-a',
        availableAssetIds: ['asset-a', 'asset-b', 'asset-c'],
      );

      final cleaned = references.without('asset-a');

      expect(cleaned.assetId, 'asset-b');
      expect(cleaned.defaultAssetId, 'asset-b');
      expect(cleaned.availableAssetIds, ['asset-b', 'asset-c']);
    });

    test('keeps the current default when deleting another pooled asset', () {
      const references = ScreenAssetReferences(
        assetId: 'asset-a',
        defaultAssetId: 'asset-a',
        availableAssetIds: ['asset-a', 'asset-b'],
      );

      final cleaned = references.without('asset-b');

      expect(cleaned.assetId, 'asset-a');
      expect(cleaned.defaultAssetId, 'asset-a');
      expect(cleaned.availableAssetIds, ['asset-a']);
    });

    test('clears selected fields when deleting the only asset', () {
      const references = ScreenAssetReferences(
        assetId: 'asset-a',
        defaultAssetId: 'asset-a',
        availableAssetIds: ['asset-a'],
      );

      final cleaned = references.without('asset-a');

      expect(cleaned.assetId, isNull);
      expect(cleaned.defaultAssetId, isNull);
      expect(cleaned.availableAssetIds, isEmpty);
    });
  });

  test('fake repository removes an asset from connected screens', () async {
    final repository = FirebaseFakeRepository();

    await repository.deleteAsset('asset1');

    final screens = await repository.getScreens('device1');
    final connectedScreen = screens.firstWhere(
      (screen) => screen.id == 'screen2',
    );
    expect(connectedScreen.assetId, 'asset2');
    expect(connectedScreen.defaultAssetId, 'asset2');
    expect(connectedScreen.availableAssetIds, ['asset2']);
    expect(await repository.getAssetsByIds(['asset1']), isEmpty);
  });

  testWidgets('My Assets offers confirmed deletion and removes the card', (
    tester,
  ) async {
    // The production grid targets a phone-width logical viewport. Keep this
    // interaction test wide enough that pre-existing tag-card wrapping does
    // not mask the deletion flow it exercises.
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _RecordingDeleteRepository();
    final authCubit = AuthCubit(repository);
    addTearDown(authCubit.close);

    final router = GoRouter(
      initialLocation: '/assets',
      routes: [
        GoRoute(
          path: '/assets',
          builder: (context, state) => AssetsView(repository: repository),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      BlocProvider.value(
        value: authCubit,
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          builder: (context, _) => MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunset'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Delete asset').first);
    await tester.pumpAndSettle();

    expect(find.text('Delete asset?'), findsOneWidget);
    expect(find.textContaining('removed from every screen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deletedAssetIds, ['asset1']);
    expect(find.text('Sunset'), findsNothing);
    expect(find.text('Asset deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingDeleteRepository extends FirebaseFakeRepository {
  final List<String> deletedAssetIds = [];

  @override
  Future<UserModel?> getCurrentUser() async => UserModel(
        id: 'user1',
        email: 'test@example.com',
        displayName: 'Test User',
      );

  @override
  Future<void> deleteAsset(String assetId) async {
    deletedAssetIds.add(assetId);
    await super.deleteAsset(assetId);
  }
}
