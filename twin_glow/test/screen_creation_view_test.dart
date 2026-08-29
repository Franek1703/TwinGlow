import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/views/screen_creation/screen_creation_view.dart';

void main() {
  testWidgets('screen type cards do not overflow on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (context, _) =>
            const MaterialApp(home: ScreenCreationView(deviceId: 'device')),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Clock'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Animation'), findsOneWidget);
    expect(find.text('Sensor'), findsOneWidget);
  });
}
