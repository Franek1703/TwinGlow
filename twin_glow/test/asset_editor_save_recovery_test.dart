import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/user_model.dart';
import 'package:twin_glow/features/asset_editor/cubit/asset_editor_cubit.dart';
import 'package:twin_glow/features/auth/cubit/auth_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/views/asset_editor/asset_editor_image_view.dart';

void main() {
  test('a corrected name clears validation and allows the next save', () async {
    final repository = _RecordingAssetRepository();
    final cubit = AssetEditorCubit(repository, 'user1', AssetType.image);
    addTearDown(cubit.close);

    await cubit.save();
    expect(cubit.state.error, 'Name is required');
    expect(repository.createdAsset, isNull);

    cubit.updateName('Recovered image');
    expect(cubit.state.error, isNull);

    await cubit.save();
    expect(cubit.state.error, isNull);
    expect(repository.createdAsset?.name, 'Recovered image');
  });

  testWidgets('correcting an empty name saves and returns from the editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _RecordingAssetRepository();
    final authCubit = AuthCubit(repository);
    addTearDown(authCubit.close);

    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/asset/create/image'),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/asset/create/image',
          builder: (context, state) =>
              AssetEditorImageView(repository: repository),
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

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    final createButton = find.text('Create Asset');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(createButton));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(repository.createdAsset, isNull);

    final nameField = find.byType(TextFormField).first;
    await tester.ensureVisible(nameField);
    await tester.pumpAndSettle();
    await tester.enterText(nameField, 'Recovered image');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsNothing);

    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(createButton));
    await tester.pumpAndSettle();

    expect(repository.createdAsset?.name, 'Recovered image');
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingAssetRepository extends FirebaseFakeRepository {
  AssetModel? createdAsset;

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
}
