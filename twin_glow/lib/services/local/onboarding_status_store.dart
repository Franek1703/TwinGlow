import 'package:shared_preferences/shared_preferences.dart';

abstract interface class OnboardingStatusStore {
  bool get hasCompletedOnboarding;

  Future<void> setHasCompletedOnboarding(bool value);
}

class LocalOnboardingStatusStore implements OnboardingStatusStore {
  static const _completedKey = 'has_completed_onboarding';

  final SharedPreferences _preferences;
  bool _hasCompletedOnboarding;

  LocalOnboardingStatusStore._(this._preferences, this._hasCompletedOnboarding);

  static Future<LocalOnboardingStatusStore> create({
    SharedPreferences? preferences,
  }) async {
    final localPreferences =
        preferences ?? await SharedPreferences.getInstance();
    final hasCompletedOnboarding =
        localPreferences.getBool(_completedKey) ?? false;

    return LocalOnboardingStatusStore._(
      localPreferences,
      hasCompletedOnboarding,
    );
  }

  @override
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  @override
  Future<void> setHasCompletedOnboarding(bool value) async {
    final wasSaved = await _preferences.setBool(_completedKey, value);
    if (!wasSaved) {
      throw StateError('Could not persist onboarding status.');
    }
    _hasCompletedOnboarding = value;
  }
}
