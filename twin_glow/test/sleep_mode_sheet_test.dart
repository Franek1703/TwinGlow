import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/device_model.dart';
import 'package:twin_glow/core/widgets/app_toggle.dart';
import 'package:twin_glow/views/device_config/sleep_mode_sheet.dart';

Widget _harness(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    minTextAdapt: true,
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('shows the stored window and does not overflow a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _harness(
        const SleepModeSheet(
          current: SleepSchedule(
            enabled: true,
            startMinute: 23 * 60,
            endMinute: 7 * 60,
            brightness: 10,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sleep mode'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
  });

  testWidgets('reads a sleep brightness of zero as Off', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SleepModeSheet(
          current: SleepSchedule(enabled: true, brightness: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('saving returns the edited schedule to the caller', (
    tester,
  ) async {
    SleepSchedule? saved;

    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              saved = await showModalBottomSheet<SleepSchedule>(
                context: context,
                builder: (_) => const SleepModeSheet(
                  current: SleepSchedule(enabled: false),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Flipping the toggle is the whole point of the sheet for a disabled device.
    await tester.tap(find.byType(AppToggle));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.enabled, isTrue);
  });

  testWidgets('dismissing without saving returns nothing', (tester) async {
    SleepSchedule? saved;
    var closed = false;

    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              saved = await showModalBottomSheet<SleepSchedule>(
                context: context,
                builder: (_) => const SleepModeSheet(
                  current: SleepSchedule(enabled: true),
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tapping the scrim dismisses the sheet; the caller must not write.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(saved, isNull);
  });
}
