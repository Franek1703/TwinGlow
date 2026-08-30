import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/screen_model.dart';
import 'package:twin_glow/core/widgets/screen_playlist_sliver.dart';
import 'package:twin_glow/features/screens_playlist/cubit/screens_playlist_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

void main() {
  test('moving a screen down persists the new playlist order', () async {
    final repository = FirebaseFakeRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    expect(_ids(cubit.state.screens), [
      'screen1',
      'screen2',
      'screen3',
      'screen4',
    ]);

    // Raw indices as SliverReorderableList reports them: dropping the first
    // card into the third slot arrives as (0, 3), not (0, 2).
    await cubit.moveScreen(0, 3);

    expect(_ids(cubit.state.screens), [
      'screen2',
      'screen3',
      'screen1',
      'screen4',
    ]);
    expect(_ids(await repository.getScreens('device1')), [
      'screen2',
      'screen3',
      'screen1',
      'screen4',
    ]);

    await cubit.close();
  });

  test('moving a screen up does not shift the target index', () async {
    final repository = FirebaseFakeRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    await cubit.moveScreen(3, 0);

    expect(_ids(cubit.state.screens), [
      'screen4',
      'screen1',
      'screen2',
      'screen3',
    ]);

    await cubit.close();
  });

  test('the new order is visible before the write is acknowledged', () async {
    final repository = FirebaseFakeRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    // Deliberately not awaited: the card has already animated into its new
    // slot, so the state has to show the new order while the write is still in
    // flight rather than snapping back for the length of the round trip.
    final pending = cubit.moveScreen(0, 3);

    expect(_ids(cubit.state.screens), [
      'screen2',
      'screen3',
      'screen1',
      'screen4',
    ]);

    await pending;
    await cubit.close();
  });

  test('a failed reorder rolls back to the previous order', () async {
    final cubit = ScreensPlaylistCubit(_ReorderFailsRepository(), 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);
    final original = _ids(cubit.state.screens);

    await cubit.moveScreen(0, 3);

    expect(_ids(cubit.state.screens), original);
    expect(cubit.state.error, isNotNull);

    await cubit.close();
  });

  test('an out-of-range or no-op move does not write', () async {
    final repository = _CountingRepository();
    final cubit = ScreensPlaylistCubit(repository, 'device1');
    await cubit.stream.firstWhere((state) => state.hasLoaded);

    await cubit.moveScreen(1, 1); // dropped back where it started
    await cubit.moveScreen(0, 0);
    await cubit.moveScreen(9, 0); // index no longer in the list

    expect(repository.reorderCalls, 0);

    await cubit.close();
  });

  testWidgets('dragging a card by its handle reports a reorder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    int? reportedOld;
    int? reportedNew;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                // Two cards, so the list is short enough not to scroll: an
                // auto-scrolling viewport carries the dragged card further
                // than the gesture alone and the drop index stops being
                // predictable.
                ScreenPlaylistSliver(
                  screens: _sensorScreens().take(2).toList(),
                  onReorder: (oldIndex, newIndex) {
                    reportedOld = oldIndex;
                    reportedNew = newIndex;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey('screen-drag-handle-a'));
    expect(handle, findsOneWidget);

    // Measure the gap to the next card rather than assuming a card height -
    // the cards scale with ScreenUtil, so a hard-coded offset silently becomes
    // a no-op drag on a different surface size.
    final from = tester.getCenter(handle);
    final to = tester.getCenter(
      find.byKey(const ValueKey('screen-drag-handle-b')),
    );
    final distance = to.dy - from.dy + 30;

    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset(from.dx, from.dy + (distance * step / 8)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Raw indices, uncorrected: dropping item 0 below item 1 is (0, 2).
    expect(reportedOld, 0);
    expect(reportedNew, 2);
  });

  testWidgets('every card carries its own drag handle', (tester) async {
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('screen-drag-handle-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-drag-handle-b')), findsOneWidget);
  });
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

class _ReorderFailsRepository extends FirebaseFakeRepository {
  @override
  Future<void> reorderScreens(String deviceId, List<String> screenIds) async {
    throw Exception('reorder failed');
  }
}

class _CountingRepository extends FirebaseFakeRepository {
  int reorderCalls = 0;

  @override
  Future<void> reorderScreens(String deviceId, List<String> screenIds) async {
    reorderCalls++;
    await super.reorderScreens(deviceId, screenIds);
  }
}
