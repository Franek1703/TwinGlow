import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_glow/config/app_router.dart';
import 'package:twin_glow/services/local/onboarding_status_store.dart';

/// The device configuration page holds the only UI for brightness, sleep mode
/// and time zone. Its route existed for a while with nothing pointing at it,
/// which made all three unreachable from the app, so this pins the path down
/// against the real router rather than a stand-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<List<String>> routePaths() async {
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
    return paths;
  }

  test('the device config route is registered', () async {
    // The exact string the app pushes: home_view and settings_view both build
    // '/device/${device.id}/config'.
    expect(await routePaths(), contains('/device/:deviceId/config'));
  });

  test('every route the app pushes to is registered', () async {
    final paths = await routePaths();

    // Static destinations pushed from the settings and home views. A route
    // removed out from under one of these is the failure this catches.
    for (final path in [
      '/provision',
      '/settings/profile',
      '/screen/create',
      '/device/:deviceId/config',
    ]) {
      expect(paths, contains(path), reason: 'nothing serves $path');
    }
  });
}
