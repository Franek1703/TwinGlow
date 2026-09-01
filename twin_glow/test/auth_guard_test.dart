import 'package:flutter_test/flutter_test.dart';
import 'package:twin_glow/config/app_router.dart';

/// Navigation used to be imperative only, so the session rules held for
/// button journeys and nothing else: a deep link to a protected route while
/// signed out rendered a dead "Not authenticated" panel instead of routing to
/// the login form. These pin the guard's decisions down.
void main() {
  group('a visitor without a session', () {
    test('is sent to the login form from a protected route', () {
      expect(
        authGuardRedirect(
          location: '/home',
          isRestoringSession: false,
          isSignedIn: false,
        ),
        '/auth',
      );
    });

    test('is sent to the login form from a deep link with parameters', () {
      expect(
        authGuardRedirect(
          location: '/device/abc123/config',
          isRestoringSession: false,
          isSignedIn: false,
        ),
        '/auth',
      );
    });

    test('is left alone on the login form', () {
      expect(
        authGuardRedirect(
          location: '/auth',
          isRestoringSession: false,
          isSignedIn: false,
        ),
        isNull,
      );
    });

    test('is left alone on onboarding', () {
      expect(
        authGuardRedirect(
          location: '/onboarding',
          isRestoringSession: false,
          isSignedIn: false,
        ),
        isNull,
      );
    });
  });

  group('a visitor with a session', () {
    test('is carried off the login form into the app', () {
      expect(
        authGuardRedirect(
          location: '/auth',
          isRestoringSession: false,
          isSignedIn: true,
        ),
        '/home',
      );
    });

    test('does not have to sit through onboarding again', () {
      expect(
        authGuardRedirect(
          location: '/onboarding',
          isRestoringSession: false,
          isSignedIn: true,
        ),
        '/home',
      );
    });

    test('keeps the protected route it asked for', () {
      expect(
        authGuardRedirect(
          location: '/device/abc123/config',
          isRestoringSession: false,
          isSignedIn: true,
        ),
        isNull,
      );
    });
  });

  group('while the stored session is still being read', () {
    // Redirecting here would throw a signed-in user onto the login form and
    // rewrite the deep link they opened, before the session has had a chance
    // to load.
    test('a protected route is left in place', () {
      expect(
        authGuardRedirect(
          location: '/home',
          isRestoringSession: true,
          isSignedIn: false,
        ),
        isNull,
      );
    });

    test('the login form is left in place', () {
      expect(
        authGuardRedirect(
          location: '/auth',
          isRestoringSession: true,
          isSignedIn: false,
        ),
        isNull,
      );
    });
  });
}
