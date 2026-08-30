import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/user_model.dart';
import 'package:twin_glow/features/asset_editor/cubit/animation_editor_cubit.dart';
import 'package:twin_glow/features/auth/cubit/auth_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';
import 'package:twin_glow/views/asset_editor/asset_editor_animation_view.dart';

void main() {
  Future<_RecordingRepository> pumpEditor(WidgetTester tester) async {
    // Matches the image editor's test surface, widened only in height for the
    // extra timeline and duration cards.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _RecordingRepository();
    final authCubit = AuthCubit(repository);
    addTearDown(authCubit.close);

    // Pushed from a host route so the editor has somewhere to pop back to,
    // the way it is reached from the asset library.
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/asset/create/animation'),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/asset/create/animation',
          builder: (context, state) =>
              AssetEditorAnimationView(repository: repository),
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
    return repository;
  }

  AnimationEditorCubit cubitOf(WidgetTester tester) {
    // BlocProvider sits below AssetEditorAnimationView, so read from a widget
    // inside the provided subtree rather than from the view itself.
    return tester
        .element(find.byKey(const Key('animation_add_frame')))
        .read<AnimationEditorCubit>();
  }

  AnimationEditorState stateOf(WidgetTester tester) => cubitOf(tester).state;

  testWidgets('opens on two frames with the timeline visible', (tester) async {
    await pumpEditor(tester);

    // The title appears twice: the app bar and the save button.
    expect(find.text('Create Animation'), findsNWidgets(2));
    expect(find.text('Frames (2/16)'), findsOneWidget);
    expect(find.text('Frame 1 duration'), findsOneWidget);
  });

  testWidgets('adding a frame updates the timeline count', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('animation_add_frame')));
    await tester.pumpAndSettle();

    expect(find.text('Frames (3/16)'), findsOneWidget);
    // The new frame is selected, so the duration control follows it.
    expect(find.text('Frame 2 duration'), findsOneWidget);
  });

  testWidgets('delete is disabled at the two-frame minimum', (tester) async {
    await pumpEditor(tester);

    final deleteButton = tester.widget<IconButton>(
      find.byKey(const Key('animation_delete_frame')),
    );
    expect(deleteButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('animation_add_frame')));
    await tester.pumpAndSettle();

    final enabled = tester.widget<IconButton>(
      find.byKey(const Key('animation_delete_frame')),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('the duration stepper moves in 50ms steps', (tester) async {
    await pumpEditor(tester);

    expect(stateOf(tester).selectedFrame.durationMs, 200);

    await tester.tap(find.byKey(const Key('animation_duration_plus')));
    await tester.pumpAndSettle();
    expect(stateOf(tester).selectedFrame.durationMs, 250);

    await tester.tap(find.byKey(const Key('animation_duration_minus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('animation_duration_minus')));
    await tester.pumpAndSettle();
    expect(stateOf(tester).selectedFrame.durationMs, 150);
  });

  testWidgets('the stepper stops at the documented duration bounds',
      (tester) async {
    await pumpEditor(tester);

    // Down to the 50ms floor.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('animation_duration_minus')));
      await tester.pumpAndSettle();
    }
    expect(stateOf(tester).selectedFrame.durationMs, 50);

    final minusAtFloor = tester.widget<IconButton>(
      find.byKey(const Key('animation_duration_minus')),
    );
    expect(minusAtFloor.onPressed, isNull);
  });

  testWidgets('play/pause toggles the preview', (tester) async {
    await pumpEditor(tester);

    expect(stateOf(tester).isPlaying, isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byKey(const Key('animation_play_pause')));
    await tester.pump();

    expect(stateOf(tester).isPlaying, isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // Stop the timer before the test ends.
    await tester.tap(find.byKey(const Key('animation_play_pause')));
    await tester.pumpAndSettle();
  });

  testWidgets('a blank animation reports the payload error and does not save',
      (tester) async {
    final repository = await pumpEditor(tester);

    final nameField = find.descendant(
      of: find.byKey(const Key('animation_name_field')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Empty');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('animation_save_action')));
    await tester.pumpAndSettle();

    expect(find.textContaining('visible pixel'), findsOneWidget);
    expect(repository.createdAsset, isNull);
  });

  testWidgets('a named animation with a drawn frame saves', (tester) async {
    final repository = await pumpEditor(tester);

    // Draw into frame 1 through the cubit the view is driving.
    final cubit = cubitOf(tester);
    final grid = AnimationFrameModel.emptyGrid();
    grid[0][0] = 0xFFFF0000;
    cubit.updatePixelData(grid);
    await tester.pumpAndSettle();

    final nameField = find.descendant(
      of: find.byKey(const Key('animation_name_field')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Blink');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('animation_save_action')));
    await tester.pumpAndSettle();

    expect(repository.createdAsset?.name, 'Blink');
    expect(repository.createdAsset?.type, AssetType.animation);
    expect(repository.createdAsset?.frames?.length, 2);
    // A successful save returns to where the editor was opened from.
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingRepository extends FirebaseFakeRepository {
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
