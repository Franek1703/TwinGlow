import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/device_header.dart';
import '../../core/widgets/screen_playlist_sliver.dart';
import '../../core/models/device_model.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/device/cubit/devices_cubit.dart';
import '../../features/screens_playlist/cubit/screens_playlist_cubit.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseRepo = FirebaseRepositoryImpl();

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

        return BlocProvider(
          create: (_) => DevicesCubit(firebaseRepo, userId),
          child: BlocBuilder<DevicesCubit, DevicesState>(
            builder: (context, devicesState) {
              if (devicesState.isInitialLoading) {
                return const Scaffold(
                  backgroundColor: AppColors.bgPrimary,
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final activeDevice = devicesState.activeDevice;
              if (activeDevice == null) {
                final loadFailed = devicesState.error != null;
                return Scaffold(
                  backgroundColor: AppColors.bgPrimary,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          loadFailed
                              ? 'Couldn\'t load devices'
                              : 'No devices found',
                          style: AppTypography.h2(context),
                        ),
                        if (loadFailed) ...[
                          SizedBox(height: AppSpacing.sm),
                          Text(
                            'Check your connection and try again.',
                            style: AppTypography.body(context),
                          ),
                        ],
                        SizedBox(height: AppSpacing.lg),
                        AppButton(
                          text: loadFailed ? 'Retry' : 'Add Device',
                          onPressed: loadFailed
                              ? () => context
                                  .read<DevicesCubit>()
                                  .loadDevices()
                              : () => context.push('/provision'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return BlocProvider(
                key: ValueKey(activeDevice.id),
                create: (_) =>
                    ScreensPlaylistCubit(firebaseRepo, activeDevice.id),
                child: _HomeContent(device: activeDevice),
              );
            },
          ),
        );
      },
    );
  }
}

class _HomeContent extends StatelessWidget {
  final DeviceModel device;

  const _HomeContent({required this.device});

  @override
  Widget build(BuildContext context) {
    // A CustomScrollView rather than a SingleChildScrollView so the playlist's
    // SliverReorderableList drags against this scrollable and can auto-scroll.
    // Shrink-wrapping a reorderable list inside a SingleChildScrollView leaves
    // it unable to scroll, and the cards are too tall to drag past the fold.
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: BlocBuilder<ScreensPlaylistCubit, ScreensPlaylistState>(
          builder: (context, state) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.xl,
                  ),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Device Header
                            DeviceHeader(
                              deviceName: device.name,
                              isOnline: device.isOnline,
                              hasSensor: device.hasSensor,
                              // Opens this device's own settings. It used to
                              // land on the global Settings tab, which no
                              // longer holds anything device-specific.
                              onTap: () =>
                                  context.push('/device/${device.id}/config'),
                            ),
                            SizedBox(height: AppSpacing.xl),
                            // Header
                            Text(
                              'Screen Playlist',
                              style: AppTypography.h2(context),
                            ),
                            SizedBox(height: AppSpacing.sm),
                            Text(
                              'Manage your device screens and sharing',
                              style: AppTypography.body(context),
                            ),
                            SizedBox(height: AppSpacing.xl),
                            // Screen list status
                            if (state.isInitialLoading)
                              const Center(child: CircularProgressIndicator())
                            else ...[
                              if (state.isRefreshing) ...[
                                const LinearProgressIndicator(),
                                SizedBox(height: AppSpacing.lg),
                              ],
                              if (state.screens.isEmpty && state.error != null)
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: AppSpacing.xl,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Couldn\'t load screens',
                                        style: AppTypography.body(context),
                                      ),
                                      TextButton(
                                        onPressed: () => context
                                            .read<ScreensPlaylistCubit>()
                                            .loadScreens(),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                )
                              else if (state.screens.isEmpty)
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: AppSpacing.xl,
                                  ),
                                  child: Text(
                                    'No screens yet',
                                    style: AppTypography.body(context),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      // Screen List
                      if (!state.isInitialLoading)
                        ScreenPlaylistSliver(
                          screens: state.screens,
                          assets: state.assets,
                          onReorder: (oldIndex, newIndex) => context
                              .read<ScreensPlaylistCubit>()
                              .moveScreen(oldIndex, newIndex),
                          onTap: (screen) async {
                            final type = screen.type.name.toLowerCase();
                            await context.push(
                              '/screen/$type/${screen.id}?deviceId=${device.id}',
                            );
                            if (context.mounted) {
                              context
                                  .read<ScreensPlaylistCubit>()
                                  .loadScreens();
                            }
                          },
                          onToggle: (screen) {
                            context
                                .read<ScreensPlaylistCubit>()
                                .toggleScreen(screen.id);
                          },
                          onDelete: (screen) {
                            context
                                .read<ScreensPlaylistCubit>()
                                .deleteScreen(screen.id);
                          },
                        ),
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            SizedBox(height: AppSpacing.lg),
                            // Add Screen Button
                            AppButton(
                              text: 'Add New Screen',
                              onPressed: () async {
                                await context.push(
                                  '/screen/create?deviceId=${device.id}',
                                );
                                if (context.mounted) {
                                  context
                                      .read<ScreensPlaylistCubit>()
                                      .loadScreens();
                                }
                              },
                              variant: AppButtonVariant.secondary,
                              fullWidth: true,
                              icon: Icon(
                                Icons.add,
                                size: 20.sp,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 100.h), // Space for bottom nav
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
