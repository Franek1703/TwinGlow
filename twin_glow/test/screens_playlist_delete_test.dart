import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/screen_model.dart';
import 'package:twin_glow/core/widgets/screen_playlist_sliver.dart';
import 'package:twin_glow/features/screens_playlist/cubit/screens_playlist_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

/// Deleting a screen was implemented on the cubit and the repository long
/// before anything called it, so these cover the path from the swipe to the
/// write - and the rollback, which is the half a user only sees when it fails.
void main() {
  test('deleting a screen removes it from the device playlist', () async {
    final repository = FirebaseFakeRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    await cubit.deleteScreen('screen2');

    expect(_ids(cubit.state.screens), ['screen1', 'screen3', 'screen4']);
    expect(_ids(await repository.getScreens('device1')), [
      'screen1',
      'screen3',
      'screen4',
    ]);

    await cubit.close();
  });

  test('the screen is gone before the write is acknowledged', () async {
    final repository = FirebaseFakeRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    // Deliberately not awaited: the card has already swiped off the list, so
    // leaving it in state until Firestore answers would show it sitting in a
    // gap it has visibly left.
    final pending = cubit.deleteScreen('screen1');

    expect(_ids(cubit.state.screens), ['screen2', 'screen3', 'screen4']);

    await pending;
    await cubit.close();
  });

  test('a failed delete puts the screen back where it was', () async {
    final cubit = ScreensPlaylistCubit(_DeleteFailsRepository(), 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);
    final original = _ids(cubit.state.screens);

    await cubit.deleteScreen('screen2');

    expect(_ids(cubit.state.screens), original);
    expect(cubit.state.error, isNotNull);

    await cubit.close();
  });

  test('deleting a screen the playlist does not hold writes nothing', () async {
    final repository = _CountingRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    await cubit.deleteScreen('screen-that-never-existed');

    expect(repository.deleteCalls, 0);
    expect(cubit.state.screens, hasLength(4));

    await cubit.close();
  });

  testWidgets('confirming the swipe reports the screen to delete', (
    tester,
  ) async {
    ScreenModel? deleted;
    await _pumpPlaylist(tester, onDelete: (screen) => deleted = screen);

    await _swipeAway(tester, 'a');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted?.id, 'a');
  });

  testWidgets('cancelling the swipe deletes nothing', (tester) async {
    ScreenModel? deleted;
    await _pumpPlaylist(tester, onDelete: (screen) => deleted = screen);

    await _swipeAway(tester, 'a');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isNull);
    // The card has to spring back, not leave a hole the list never refills.
    expect(find.byKey(const ValueKey('screen-drag-handle-a')), findsOneWidget);
  });

  testWidgets('cards are not swipeable when no delete handler is given', (
    tester,
  ) async {
    await _pumpPlaylist(tester, onDelete: null);

    expect(find.byType(Dismissible), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPlaylist(
  WidgetTester tester, {
  required void Function(ScreenModel screen)? onDelete,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ScreenPlaylistSliver(
                screens: _sensorScreens(),
                onReorder: (_, _) {},
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drags the card left far enough for [Dismissible] to ask for confirmation.
Future<void> _swipeAway(WidgetTester tester, String screenId) async {
  await tester.drag(
    find.byKey(ValueKey('screen-dismiss-$screenId')),
    const Offset(-400, 0),
  );
  await tester.pumpAndSettle();
}

List<String> _ids(List<ScreenModel> screens) =>
    screens.map((screen) => screen.id).toList();

/// Sensor screens render from their config alone - no assets to stub, and no
/// ticking clock to leave a timer pending at the end of the test.
List<ScreenModel> _sensorScreens() {
  return ['a', 'b', 'c']
      .map(
        (id) => ScreenModel(
          id: id,
          type: ScreenType.sensor,
          name: 'Screen $id',
          config: const {
            'showTemperature': true,
            'showHumidity': false,
            'showPressure': false,
            'useMetricUnits': true,
          },
        ),
      )
      .toList();
}

class _DeleteFailsRepository extends FirebaseFakeRepository {
  @override
  Future<void> deleteScreen(String deviceId, String screenId) async {
    throw Exception('delete failed');
  }
}

class _CountingRepository extends FirebaseFakeRepository {
  int deleteCalls = 0;

  @override
  Future<void> deleteScreen(String deviceId, String screenId) async {
    deleteCalls++;
    await super.deleteScreen(deviceId, screenId);
  }
}
