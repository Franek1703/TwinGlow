import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_glow/config/app_router.dart';
import 'package:twin_glow/services/local/onboarding_status_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('onboarding completion persists between store instances', () async {
    final store = await LocalOnboardingStatusStore.create();
    expect(store.hasCompletedOnboarding, isFalse);

    await store.setHasCompletedOnboarding(true);
    final reloadedStore = await LocalOnboardingStatusStore.create();

    expect(reloadedStore.hasCompletedOnboarding, isTrue);

    await reloadedStore.setHasCompletedOnboarding(false);
    final resetStore = await LocalOnboardingStatusStore.create();

    expect(resetStore.hasCompletedOnboarding, isFalse);
  });

  test('startup route skips onboarding after completion', () async {
    final store = await LocalOnboardingStatusStore.create();
    final onboardingRouter = createAppRouter(store);
    addTearDown(onboardingRouter.dispose);
    expect(
      onboardingRouter.routeInformationProvider.value.uri.path,
      '/onboarding',
    );

    await store.setHasCompletedOnboarding(true);
    final returningUserRouter = createAppRouter(store);
    addTearDown(returningUserRouter.dispose);
    expect(
      returningUserRouter.routeInformationProvider.value.uri.path,
      '/auth',
    );
  });
}
