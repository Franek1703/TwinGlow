import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/device_header.dart';
import '../../core/widgets/screen_card.dart';
import '../../core/models/device_model.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/device/cubit/devices_cubit.dart';
import '../../features/screens_playlist/cubit/screens_playlist_cubit.dart';
import '../../services/firebase/firebase_fake_repository.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseRepo = FirebaseFakeRepository();

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
          providers: [
            BlocProvider(
              create: (_) => DevicesCubit(firebaseRepo, userId),
            ),
            BlocProvider(
              create: (_) {
                final devicesCubit = DevicesCubit(firebaseRepo, userId);
                devicesCubit.loadDevices();
                return devicesCubit;
              },
            ),
          ],
          child: BlocBuilder<DevicesCubit, DevicesState>(
            builder: (context, devicesState) {
              final activeDevice = devicesState.activeDevice;
              if (activeDevice == null) {
                return Scaffold(
                  backgroundColor: AppColors.bgPrimary,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No devices found',
                          style: AppTypography.h2(context),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        AppButton(
                          text: 'Add Device',
                          onPressed: () => context.go('/provision'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return BlocProvider(
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
    return Scaffold(
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
              // Device Header
              DeviceHeader(
                deviceName: device.name,
                isOnline: device.isOnline,
                hasSensor: device.hasSensor,
                onTap: () => context.go('/settings'),
              ),
              SizedBox(height: AppSpacing.xl),
              // Header
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Screen Playlist',
                    style: AppTypography.h2(context),
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'Manage your device screens and sharing',
                    style: AppTypography.body(context),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xl),
              // Screen List
              BlocBuilder<ScreensPlaylistCubit, ScreensPlaylistState>(
                builder: (context, state) {
                  if (state.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  return Column(
                    children: [
                      ...state.screens.map((screen) => Padding(
                            padding: EdgeInsets.only(bottom: AppSpacing.lg),
                            child: ScreenCard(
                              screen: screen,
                              onTap: () {
                                final type = screen.type.name.toLowerCase();
                                context.push('/screen/$type/${screen.id}');
                              },
                              onToggle: () {
                                context
                                    .read<ScreensPlaylistCubit>()
                                    .toggleScreen(screen.id);
                              },
                            ),
                          )),
                    ],
                  );
                },
              ),
              SizedBox(height: AppSpacing.lg),
              // Add Screen Button
              AppButton(
                text: 'Add New Screen',
                onPressed: () {
                  context.push('/screen/create');
                },
                variant: AppButtonVariant.secondary,
                fullWidth: true,
                icon: Icon(Icons.add, size: 20.sp, color: AppColors.textPrimary),
              ),
              SizedBox(height: 100.h), // Space for bottom nav
            ],
          ),
        ),
      ),
    );
  }
}
