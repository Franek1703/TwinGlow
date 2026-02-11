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

class ScreenEditorClockView extends StatelessWidget {
  final String screenId;

  const ScreenEditorClockView({super.key, required this.screenId});

  @override
  Widget build(BuildContext context) {
    // TODO: Load screen from repository
    final mockScreen = ScreenModel(
      id: screenId,
      type: ScreenType.clock,
      name: 'Digital Clock',
      enabled: true,
    );

    return BlocProvider(
      create: (_) => ScreenEditorClockCubit(mockScreen),
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
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  onPressed: state.isLoading
                      ? null
                      : () {
                          context.read<ScreenEditorClockCubit>().save().then((_) {
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
            child: BlocBuilder<ScreenEditorClockCubit, ScreenEditorClockState>(
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
                              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Center(
                              child: _ClockPreview(
                                digitColor: state.digitColor,
                                colonColor: state.colonColor,
                                showSeconds: state.showSeconds,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Settings
                    Text(
                      'Settings',
                      style: AppTypography.h2(context),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Show Seconds Toggle
                    AppCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show Seconds',
                                style: AppTypography.h4(context),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'Display seconds in clock',
                                style: AppTypography.small(context),
                              ),
                            ],
                          ),
                          _ToggleSwitch(
                            enabled: state.showSeconds,
                            onChanged: (value) {
                              context.read<ScreenEditorClockCubit>().toggleSeconds();
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Color Configuration
                    Text(
                      'Colors',
                      style: AppTypography.h3(context),
                    ),
                    SizedBox(height: AppSpacing.md),
                    ColorPicker(
                      initialColor: state.digitColor,
                      label: 'Digit Color',
                      onColorChanged: (color) {
                        context.read<ScreenEditorClockCubit>().updateDigitColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.md),
                    ColorPicker(
                      initialColor: state.colonColor,
                      label: 'Colon Color',
                      onColorChanged: (color) {
                        context.read<ScreenEditorClockCubit>().updateColonColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.md),
                    ColorPicker(
                      initialColor: state.backgroundColor,
                      label: 'Background Color',
                      onColorChanged: (color) {
                        context.read<ScreenEditorClockCubit>().updateBackgroundColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.xxl),
                    // Save Button
                    AppButton(
                      text: 'Save Configuration',
                      onPressed: () {
                        context.read<ScreenEditorClockCubit>().save().then((_) {
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
  }
}

class _ClockPreview extends StatelessWidget {
  final Color digitColor;
  final Color colonColor;
  final bool showSeconds;

  const _ClockPreview({
    required this.digitColor,
    required this.colonColor,
    required this.showSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DigitDisplay(text: hour, color: digitColor),
        SizedBox(width: 8.w),
        _ColonDisplay(color: colonColor),
        SizedBox(width: 8.w),
        _DigitDisplay(text: minute, color: digitColor),
        if (showSeconds) ...[
          SizedBox(width: 8.w),
          _ColonDisplay(color: colonColor),
          SizedBox(width: 8.w),
          _DigitDisplay(text: second, color: digitColor),
        ],
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

class _ToggleSwitch extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleSwitch({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 48.w,
        height: 28.h,
        decoration: BoxDecoration(
          gradient: enabled ? AppColors.primaryGradient : null,
          color: enabled ? null : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(9999),
          border: enabled
              ? null
              : Border.all(color: AppColors.borderColor, width: 1),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              left: enabled ? 20.w : 4.w,
              top: 4.h,
              child: Container(
                width: 20.w,
                height: 20.w,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
