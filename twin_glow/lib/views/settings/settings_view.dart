import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/models/device_model.dart';
import '../../core/widgets/app_card.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/device/cubit/devices_cubit.dart';
import '../../features/pairing/cubit/pairing_cubit.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final userId = authState.user?.id ?? '';
        
        if (userId.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (authState.isLoading)
                    const CircularProgressIndicator()
                  else
                    Column(
                      children: [
                        Text(
                          'Not authenticated',
                          style: AppTypography.h2(context),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        AppButton(
                          text: 'Sign In',
                          onPressed: () => context.go('/auth'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }

        return MultiBlocProvider(
          key: ValueKey(userId),
          providers: [
            BlocProvider(
              create: (_) => PairingCubit(FirebaseRepositoryImpl(), userId),
            ),
            BlocProvider(
              create: (_) => DevicesCubit(FirebaseRepositoryImpl(), userId),
            ),
          ],
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Settings',
                  style: AppTypography.h1(context),
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Manage your account and devices',
                  style: AppTypography.body(context),
                ),
                SizedBox(height: AppSpacing.xl),
                // Account Section
                _SectionTitle('Account'),
                SizedBox(height: AppSpacing.md),
                AppCard(
                  onTap: () {
                    context.push('/settings/profile');
                  },
                  hoverable: true,
                  child: Row(
                    children: [
                      Container(
                        width: 48.w,
                        height: 48.w,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person,
                          size: 24.sp,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authState.user?.displayName ?? 'User',
                              style: AppTypography.h4(context),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              authState.user?.email ?? '',
                              style: AppTypography.small(context),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                        size: 20.sp,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.xl),
                // Pairing Section
                _SectionTitle('Pairing'),
                SizedBox(height: AppSpacing.md),
                BlocBuilder<PairingCubit, PairingState>(
                  builder: (context, state) {
                    final pairing = state.pairing;
                    return AppCard(
                      onTap: state.isInitialLoading || state.error != null
                          ? null
                          : () async {
                              await context.push('/settings/pairing');
                              if (context.mounted) {
                                context.read<PairingCubit>().loadPairing();
                              }
                            },
                      hoverable: true,
                      child: state.isInitialLoading
                          ? const Center(child: CircularProgressIndicator())
                          : state.error != null
                          ? Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: AppColors.statusError,
                                ),
                                SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    'Couldn\'t load pairing status',
                                    style: AppTypography.body(context),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context
                                      .read<PairingCubit>()
                                      .loadPairing(),
                                  child: const Text('Retry'),
                                ),
                              ],
                            )
                          : Row(
                        children: [
                          Container(
                            width: 40.w,
                            height: 40.w,
                            decoration: BoxDecoration(
                              color: AppColors.accentMagenta.withOpacity(0.2),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusLg),
                            ),
                            child: Icon(
                              Icons.link,
                              size: 20.sp,
                              color: AppColors.accentMagenta,
                            ),
                          ),
                          SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pairing.isPaired
                                      ? 'Paired with ${pairing.pairedUserName}'
                                      : 'Not paired',
                                  style: AppTypography.h4(context),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  pairing.isPaired
                                      ? '${pairing.sharedScreensCount} shared screens'
                                      : 'Tap to pair with another user',
                                  style: AppTypography.small(context),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: AppColors.textMuted,
                            size: 20.sp,
                          ),
                          if (state.isRefreshing) ...[
                            SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 14.w,
                              height: 14.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                SizedBox(height: AppSpacing.xl),
                // Devices Section
                _SectionTitle('Devices'),
                SizedBox(height: AppSpacing.md),
                // One card per owned device, each opening that device's own
                // configuration. This used to be a hardcoded placeholder card.
                BlocBuilder<DevicesCubit, DevicesState>(
                  builder: (context, deviceState) {
                    if (deviceState.isInitialLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (deviceState.devices.isEmpty) {
                      return AppCard(
                        child: Text(
                          deviceState.error != null
                              ? 'Couldn\'t load devices'
                              : 'No devices yet',
                          style: AppTypography.body(context).copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final device in deviceState.devices) ...[
                          _DeviceCard(device: device),
                          SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    );
                  },
                ),
                SizedBox(height: AppSpacing.md),
                AppButton(
                  text: 'Add New Device',
                  onPressed: () => context.push('/provision'),
                  variant: AppButtonVariant.secondary,
                  fullWidth: true,
                ),
                SizedBox(height: AppSpacing.xl),
                // Sign Out
                BlocListener<AuthCubit, AuthState>(
                  listener: (context, state) {
                    if (!state.isAuthenticated && !state.isLoading) {
                      context.go('/auth');
                    }
                  },
                  child: AppButton(
                    text: 'Sign Out',
                    onPressed: () {
                      context.read<AuthCubit>().signOut();
                    },
                    variant: AppButtonVariant.danger,
                    fullWidth: true,
                    icon: Icon(
                      Icons.logout,
                      size: 20.sp,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: 100.h), // Space for bottom nav
              ],
            ),
          ),
        ),
      ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTypography.small(context).copyWith(
        color: AppColors.textMuted,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A device in the Settings list. Tapping it opens that device's configuration
/// (brightness, sleep mode, time zone).
class _DeviceCard extends StatelessWidget {
  final DeviceModel device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final statusColor = device.isOnline
        ? AppColors.statusOnline
        : AppColors.statusOffline;

    return AppCard(
      onTap: () => context.push('/device/${device.id}/config'),
      hoverable: true,
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Icon(
              Icons.phone_android,
              size: 20.sp,
              color: Colors.white,
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: AppTypography.h4(context)),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(
                      device.isOnline ? Icons.wifi : Icons.wifi_off,
                      size: 12.sp,
                      color: statusColor,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      device.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(fontSize: 12.sp, color: statusColor),
                    ),
                    if (device.hasSensor) ...[
                      SizedBox(width: 12.w),
                      Icon(
                        Icons.device_thermostat,
                        size: 12.sp,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'BME680',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20.sp),
        ],
      ),
    );
  }
}
