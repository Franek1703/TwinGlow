import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/core/models/asset_model.dart';
import 'package:twin_glow/core/models/screen_model.dart';
import 'package:twin_glow/core/widgets/screen_preview.dart';
import 'package:twin_glow/features/screen_editor/cubit/screen_editor_clock_cubit.dart';
import 'package:twin_glow/services/firebase/firebase_fake_repository.dart';

void main() {
  test(
    'assetIdsForScreenPreview keeps the pool order and legacy references',
    () {
      final screen = ScreenModel(
        id: 'screen',
        type: ScreenType.image,
        assetId: 'legacy',
        defaultAssetId: 'second',
        availableAssetIds: const ['first', 'second'],
      );

      expect(assetIdsForScreenPreview(screen), ['first', 'second', 'legacy']);
    },
  );

  testWidgets('multi-asset preview starts at the default and pages in a loop', (
    tester,
  ) async {
    final screen = ScreenModel(
      id: 'screen',
      type: ScreenType.image,
      defaultAssetId: 'second',
      availableAssetIds: const ['first', 'second'],
    );
    final assets = [
      AssetModel(
        id: 'first',
        name: 'First image',
        type: AssetType.image,
        pixelData: _grid(0x00D9FF),
      ),
      AssetModel(
        id: 'second',
        name: 'Second image',
        type: AssetType.image,
        pixelData: _grid(0xFF006E),
      ),
    ];

    await tester.pumpWidget(
      _harness(ScreenPreview(screen: screen, assets: assets)),
    );

    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('screen-preview-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('screen-preview-previous')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('sensor preview reflects its saved fields and units', (
    tester,
  ) async {
    final screen = ScreenModel(
      id: 'sensor',
      type: ScreenType.sensor,
      config: const {
        'showTemperature': true,
        'showHumidity': false,
        'showPressure': false,
        'useMetricUnits': false,
      },
    );

    await tester.pumpWidget(_harness(ScreenPreview(screen: screen)));

    expect(find.text('72°F'), findsOneWidget);
    expect(find.text('Humidity'), findsNothing);
    expect(find.text('Pressure'), findsNothing);
  });

  for (final showSeconds in [true, false, null]) {
    testWidgets('clock preview respects showSeconds=$showSeconds', (
      tester,
    ) async {
      final screen = ScreenModel(
        id: 'clock',
        type: ScreenType.clock,
        config: {'showSeconds': ?showSeconds},
      );

      await tester.pumpWidget(_harness(ScreenPreview(screen: screen)));

      expect(find.text(':'), findsNWidgets((showSeconds ?? true) ? 2 : 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final initialShowSeconds in [true, false, null]) {
    test(
      'clock editor loads and saves showSeconds=$initialShowSeconds',
      () async {
        final repository = FirebaseFakeRepository();
        final screen = ScreenModel(
          id: 'clock',
          type: ScreenType.clock,
          config: initialShowSeconds == null
              ? null
              : {'showSeconds': initialShowSeconds},
        );
        if (screen.config != null) {
          await repository.createScreen('device1', screen);
        }
        final cubit = ScreenEditorClockCubit(repository, 'device1', screen);
        addTearDown(cubit.close);

        final expectedInitialValue = initialShowSeconds ?? true;
        expect(cubit.state.showSeconds, expectedInitialValue);
        await cubit.save();
        expect(cubit.state.error, isNull);
        final savedScreen = (await repository.getScreens(
          'device1',
        )).firstWhere((screen) => screen.id == cubit.state.screen.id);
        expect(savedScreen.config?['showSeconds'], expectedInitialValue);

        final reopenedCubit = ScreenEditorClockCubit(
          repository,
          'device1',
          savedScreen,
        );
        addTearDown(reopenedCubit.close);
        reopenedCubit.toggleSeconds();
        reopenedCubit.updateDigitColor(Colors.red);
        await reopenedCubit.save();
        expect(reopenedCubit.state.error, isNull);
        final updatedScreen = (await repository.getScreens(
          'device1',
        )).firstWhere((screen) => screen.id == savedScreen.id);
        expect(updatedScreen.config?['showSeconds'], !expectedInitialValue);
      },
    );
  }
}

Widget _harness(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, height: 200, child: child)),
      ),
    ),
  );
}

List<List<int>> _grid(int color) {
  return List.generate(16, (_) => List.filled(16, color));
}
