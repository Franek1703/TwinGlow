import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/user_model.dart';
import 'package:twin_glow/features/auth/cubit/auth_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/views/assets/assets_view.dart';

void main() {
  testWidgets('returning from image creation reloads the assets list', (
    tester,
  ) async {
    // Keep this navigation/state test wide enough that unrelated compact-layout
    // overflows cannot mask the provider-scope regression it is exercising.
    tester.view.physicalSize = const Size(800, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _CountingAssetsRepository();
    final authCubit = AuthCubit(repository);
    addTearDown(authCubit.close);

    final router = GoRouter(
      initialLocation: '/assets',
      routes: [
        GoRoute(
          path: '/assets',
          builder: (context, state) => AssetsView(repository: repository),
        ),
        GoRoute(
          path: '/asset/create/image',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Finish creating'),
              ),
            ),
          ),
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

    expect(repository.userAssetsRequests, 1);
    expect(tester.takeException(), isNull);

    final createButton = find.text('Create New Image');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(createButton));
    await tester.pumpAndSettle();
    expect(find.text('Finish creating'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Finish creating'));
    await tester.pumpAndSettle();

    expect(repository.userAssetsRequests, 2);
    expect(tester.takeException(), isNull);
  });
}

class _CountingAssetsRepository extends FirebaseFakeRepository {
  int userAssetsRequests = 0;

  @override
  Future<UserModel?> getCurrentUser() async => UserModel(
    id: 'user1',
    email: 'test@example.com',
    displayName: 'Test User',
  );

  @override
  Future<List<AssetModel>> getUserAssets(String userId) async {
    userAssetsRequests++;
    return const [];
  }

  @override
  Future<List<AssetModel>> getDefaultAssets() async => const [];
}
