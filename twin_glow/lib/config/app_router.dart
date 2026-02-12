import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import '../../views/onboarding/onboarding_view.dart';
import '../../views/auth/auth_view.dart';
import '../../views/home/home_view.dart';
import '../../views/assets/assets_view.dart';
import '../../views/settings/settings_view.dart';
import '../../views/device_provisioning/device_provisioning_view.dart';
import '../../views/screen_editor/screen_editor_clock_view.dart';
import '../../views/screen_editor/screen_editor_image_view.dart';
import '../../views/screen_editor/screen_editor_sensor_view.dart';
import '../../views/asset_editor/asset_editor_image_view.dart';
import '../../views/asset_editor/asset_editor_animation_view.dart';
import '../../views/pairing/pairing_management_view.dart';
import '../../views/profile/profile_view.dart';
import '../../views/device_config/device_config_view.dart';
import '../../views/screen_creation/screen_creation_view.dart';

final appRouter = GoRouter(
  initialLocation: '/onboarding',
  routes: [
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingView(),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthView(),
    ),
    GoRoute(
      path: '/provision',
      builder: (context, state) => const DeviceProvisioningView(),
    ),
    GoRoute(
      path: '/screen/create',
      builder: (context, state) {
        final deviceId = state.uri.queryParameters['deviceId'];
        return ScreenCreationView(deviceId: deviceId);
      },
    ),
    GoRoute(
      path: '/settings/profile',
      builder: (context, state) => const ProfileView(),
    ),
    GoRoute(
      path: '/device/:deviceId/config',
      builder: (context, state) {
        final deviceId = state.pathParameters['deviceId']!;
        return DeviceConfigView(deviceId: deviceId);
      },
    ),
    // Main app shell with bottom navigation
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const HomeView(),
          ),
        ),
        GoRoute(
          path: '/assets',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const AssetsView(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const SettingsView(),
          ),
        ),
      ],
    ),
    // Screen editors
    GoRoute(
      path: '/screen/clock/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final deviceId = state.uri.queryParameters['deviceId'];
        return ScreenEditorClockView(screenId: id, deviceId: deviceId);
      },
    ),
    GoRoute(
      path: '/screen/image/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final deviceId = state.uri.queryParameters['deviceId'];
        return ScreenEditorImageView(screenId: id, deviceId: deviceId);
      },
    ),
    GoRoute(
      path: '/screen/sensor/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final deviceId = state.uri.queryParameters['deviceId'];
        return ScreenEditorSensorView(screenId: id, deviceId: deviceId);
      },
    ),
    // Asset editors
    GoRoute(
      path: '/asset/create/image',
      builder: (context, state) => const AssetEditorImageView(),
    ),
    GoRoute(
      path: '/asset/create/animation',
      builder: (context, state) => const AssetEditorAnimationView(),
    ),
    GoRoute(
      path: '/asset/edit/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return AssetEditorImageView(assetId: id);
      },
    ),
    // Pairing
    GoRoute(
      path: '/settings/pairing',
      builder: (context, state) => const PairingManagementView(),
    ),
  ],
);

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNav(),
    );
  }
}

class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home,
                label: 'Home',
                path: '/home',
                isActive: currentLocation == '/home',
              ),
              _NavItem(
                icon: Icons.image,
                label: 'Assets',
                path: '/assets',
                isActive: currentLocation == '/assets',
              ),
              _NavItem(
                icon: Icons.settings,
                label: 'Settings',
                path: '/settings',
                isActive: currentLocation == '/settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final bool isActive;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(path),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24.sp,
              color: isActive ? AppColors.accentCyan : AppColors.textMuted,
            ),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: isActive ? AppColors.accentCyan : AppColors.textMuted,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

