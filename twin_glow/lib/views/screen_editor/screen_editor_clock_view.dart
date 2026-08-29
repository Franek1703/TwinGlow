import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/screen_model.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/color_picker.dart';
import '../../features/screen_editor/cubit/screen_editor_clock_cubit.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class ScreenEditorClockView extends StatelessWidget {
  final String screenId;
  final String? deviceId;

  const ScreenEditorClockView({
    super.key,
    required this.screenId,
    this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    if (deviceId == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: const Text('Clock Screen Editor'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Device ID is required')),
      );
    }

    final firebaseRepo = FirebaseRepositoryImpl();

    // Try to load existing screen, or create new one
    return FutureBuilder<ScreenModel?>(
      future: _loadScreen(firebaseRepo, deviceId!, screenId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: const Text('Clock Screen Editor'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final screen =
            snapshot.data ??
            ScreenModel(
              id: screenId,
              type: ScreenType.clock,
              name: 'Digital Clock',
              enabled: true,
            );

        return BlocProvider(
          create: (_) =>
              ScreenEditorClockCubit(firebaseRepo, deviceId!, screen),
          child: Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: const Text('Clock Screen Editor'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                BlocBuilder<ScreenEditorClockCubit, ScreenEditorClockState>(
                  builder: (context, state) {
                    return IconButton(
                      icon: state.isLoading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check),
                      onPressed: state.isLoading
                          ? null
                          : () {
                              context
                                  .read<ScreenEditorClockCubit>()
                                  .save()
                                  .then((_) {
                                    context.pop();
                                  });
                            },
                    );
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.xl),
                child:
                    BlocBuilder<ScreenEditorClockCubit, ScreenEditorClockState>(
                      builder: (context, state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Preview Section
                            AppCard(
                              child: Column(
                                children: [
                                  Text(
                                    'Preview',
                                    style: AppTypography.h4(context),
                                  ),
                                  SizedBox(height: AppSpacing.lg),
                                  Container(
                                    width: double.infinity,
                                    height: 200.h,
                                    decoration: BoxDecoration(
                                      color: state.backgroundColor,
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusLg,
                                      ),
                                      border: Border.all(
                                        color: AppColors.borderSubtle,
                                      ),
                                    ),
                                    child: Center(
                                      child: _ClockPreview(
                                        digitColor: state.digitColor,
                                        colonColor: state.colonColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: AppSpacing.xl),
                            // Color Configuration
                            Text('Colors', style: AppTypography.h3(context)),
                            SizedBox(height: AppSpacing.md),
                            ColorPicker(
                              initialColor: state.digitColor,
                              label: 'Digit Color',
                              onColorChanged: (color) {
                                context
                                    .read<ScreenEditorClockCubit>()
                                    .updateDigitColor(color);
                              },
                            ),
                            SizedBox(height: AppSpacing.md),
                            ColorPicker(
                              initialColor: state.colonColor,
                              label: 'Colon Color',
                              onColorChanged: (color) {
                                context
                                    .read<ScreenEditorClockCubit>()
                                    .updateColonColor(color);
                              },
                            ),
                            SizedBox(height: AppSpacing.md),
                            ColorPicker(
                              initialColor: state.backgroundColor,
                              label: 'Background Color',
                              onColorChanged: (color) {
                                context
                                    .read<ScreenEditorClockCubit>()
                                    .updateBackgroundColor(color);
                              },
                            ),
                            SizedBox(height: AppSpacing.xxl),
                            // Save Button
                            AppButton(
                              text: 'Save Configuration',
                              onPressed: () {
                                context
                                    .read<ScreenEditorClockCubit>()
                                    .save()
                                    .then((_) {
                                      context.pop();
                                    });
                              },
                              fullWidth: true,
                              size: AppButtonSize.lg,
                            ),
                          ],
                        );
                      },
                    ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<ScreenModel?> _loadScreen(
    FirebaseRepositoryImpl repo,
    String deviceId,
    String screenId,
  ) async {
    try {
      final screens = await repo.getScreens(deviceId);
      try {
        return screens.firstWhere((s) => s.id == screenId);
      } catch (e) {
        return null; // Screen doesn't exist yet
      }
    } catch (e) {
      return null;
    }
  }
}

class _ClockPreview extends StatelessWidget {
  final Color digitColor;
  final Color colonColor;

  const _ClockPreview({
    required this.digitColor,
    required this.colonColor,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DigitDisplay(text: hour, color: digitColor),
        SizedBox(width: 8.w),
        _ColonDisplay(color: colonColor),
        SizedBox(width: 8.w),
        _DigitDisplay(text: minute, color: digitColor),
      ],
    );
  }
}

class _DigitDisplay extends StatelessWidget {
  final String text;
  final Color color;

  const _DigitDisplay({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 48.sp,
        fontWeight: FontWeight.bold,
        color: color,
        fontFeatures: [const FontFeature.tabularFigures()],
      ),
    );
  }
}

class _ColonDisplay extends StatelessWidget {
  final Color color;

  const _ColonDisplay({required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      ':',
      style: TextStyle(
        fontSize: 48.sp,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }
}
