import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_glow/config/app_router.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/user_model.dart';
import 'package:twin_glow/features/auth/cubit/auth_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/services/local/onboarding_status_store.dart';
import 'package:twin_glow/views/asset_editor/asset_editor_animation_view.dart';
import 'package:twin_glow/views/asset_editor/asset_editor_image_view.dart';
import 'package:twin_glow/views/assets/assets_view.dart';

/// Editing used to send every asset to the image editor, which silently
/// flattened an animation to its first frame on the next save. These cover both
/// halves of the fix: the link the library builds, and the dispatch the router
/// performs on it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
  });

  group('router dispatch', () {
    test('an animation link opens the animation editor', () {
      final editor = assetEditorFor(assetId: 'anim1', type: 'animation');

      expect(editor, isA<AssetEditorAnimationView>());
      expect((editor as AssetEditorAnimationView).assetId, 'anim1');
    });

    test('an image link opens the image editor', () {
      final editor = assetEditorFor(assetId: 'img1', type: 'image');

      expect(editor, isA<AssetEditorImageView>());
      expect((editor as AssetEditorImageView).assetId, 'img1');
    });

    test('a link with no type keeps the previous image behaviour', () {
      expect(
        assetEditorFor(assetId: 'img1', type: null),
        isA<AssetEditorImageView>(),
      );
    });

    test('the asset editor routes are registered', () async {
      final store = await LocalOnboardingStatusStore.create();
      final router = createAppRouter(store);
      addTearDown(router.dispose);

      final paths = <String>[];
      void walk(List<RouteBase> routes) {
        for (final route in routes) {
          if (route is GoRoute) paths.add(route.path);
          walk(route.routes);
        }
      }

      walk(router.configuration.routes);

      expect(
        paths,
        containsAll([
          '/asset/create/image',
          '/asset/import/image',
          '/asset/create/animation',
          '/asset/import/animation',
          '/asset/edit/:id',
        ]),
      );
    });
  });

  group('the library link carries the asset type', () {
    Future<String?> tapFirstAssetCard(
      WidgetTester tester,
      AssetModel asset,
    ) async {
      // Matches asset_deletion_test: the production grid targets a phone-width
      // viewport, and a narrower surface trips pre-existing card wrapping that
      // has nothing to do with the link being asserted.
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _AssetLibraryRepository([asset]);
      final authCubit = AuthCubit(repository);
      addTearDown(authCubit.close);

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/assets',
        routes: [
          GoRoute(
            path: '/assets',
            builder: (context, state) => AssetsView(repository: repository),
          ),
          GoRoute(
            path: '/asset/edit/:id',
            builder: (context, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('editor stub'));
            },
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

      await tester.tap(find.text(asset.name));
      await tester.pumpAndSettle();

      return pushedLocation;
    }

    testWidgets('an animation card links to the animation editor',
        (tester) async {
      final location = await tapFirstAssetCard(
        tester,
        AssetModel(
          id: 'anim1',
          name: 'Blink',
          type: AssetType.animation,
          frames: [
            AnimationFrameModel.blank(),
            AnimationFrameModel.blank(),
          ],
        ),
      );

      expect(location, '/asset/edit/anim1?type=animation');
    });

    testWidgets('an image card still links to the image editor',
        (tester) async {
      final location = await tapFirstAssetCard(
        tester,
        AssetModel(id: 'img1', name: 'Heart', type: AssetType.image),
      );

      expect(location, '/asset/edit/img1?type=image');
    });
  });
}

class _AssetLibraryRepository extends FirebaseFakeRepository {
  final List<AssetModel> assets;

  _AssetLibraryRepository(this.assets);

  @override
  Future<UserModel?> getCurrentUser() async => UserModel(
        id: 'user1',
        email: 'test@example.com',
        displayName: 'Test User',
      );

  @override
  Future<List<AssetModel>> getUserAssets(String userId) async => assets;

  @override
  Future<List<AssetModel>> getDefaultAssets() async => const [];
}
