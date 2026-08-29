import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twin_glow/views/device_provisioning/device_provisioning_view.dart';

void main() {
  testWidgets('provisioning returns to the page that pushed it', (
    tester,
  ) async {
    final router = _router('/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_harness(router));
    await tester.tap(find.text('Open provisioning'));
    await tester.pumpAndSettle();
    expect(find.text('Device Provisioning'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Home page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct provisioning entry has a safe back fallback', (
    tester,
  ) async {
    final router = _router('/provision');
    addTearDown(router.dispose);

    await tester.pumpWidget(_harness(router));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Home page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Home page'),
                TextButton(
                  onPressed: () => context.push('/provision'),
                  child: const Text('Open provisioning'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/provision',
        builder: (context, state) => const DeviceProvisioningView(),
      ),
    ],
  );
}

Widget _harness(GoRouter router) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp.router(routerConfig: router),
  );
}
