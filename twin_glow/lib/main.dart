import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'services/local/onboarding_status_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onboardingStatusStore = await LocalOnboardingStatusStore.create();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }
  runApp(App(onboardingStatusStore: onboardingStatusStore));
}
