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
import '../../features/screen_editor/cubit/screen_editor_sensor_cubit.dart';

class ScreenEditorSensorView extends StatelessWidget {
  final String screenId;

  const ScreenEditorSensorView({super.key, required this.screenId});

  @override
  Widget build(BuildContext context) {
    // TODO: Load screen from repository
    final mockScreen = ScreenModel(
      id: screenId,
      type: ScreenType.sensor,
      name: 'Sensor Display',
      enabled: true,
    );

    return BlocProvider(
      create: (_) => ScreenEditorSensorCubit(mockScreen),
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: const Text('Sensor Screen Editor'),
          actions: [
            BlocBuilder<ScreenEditorSensorCubit, ScreenEditorSensorState>(
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
                          context.read<ScreenEditorSensorCubit>().save().then((_) {
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
            child: BlocBuilder<ScreenEditorSensorCubit, ScreenEditorSensorState>(
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
                              child: _SensorPreview(
                                showTemperature: state.showTemperature,
                                showHumidity: state.showHumidity,
                                showPressure: state.showPressure,
                                useMetricUnits: state.useMetricUnits,
                                numberColor: state.numberColor,
                                accentColor: state.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Display Values
                    Text(
                      'Display Values',
                      style: AppTypography.h2(context),
                    ),
                    SizedBox(height: AppSpacing.md),
                    _CheckboxOption(
                      label: 'Temperature',
                      value: state.showTemperature,
                      onChanged: (value) {
                        context.read<ScreenEditorSensorCubit>().toggleTemperature();
                      },
                    ),
                    SizedBox(height: AppSpacing.sm),
                    _CheckboxOption(
                      label: 'Humidity',
                      value: state.showHumidity,
                      onChanged: (value) {
                        context.read<ScreenEditorSensorCubit>().toggleHumidity();
                      },
                    ),
                    SizedBox(height: AppSpacing.sm),
                    _CheckboxOption(
                      label: 'Pressure',
                      value: state.showPressure,
                      onChanged: (value) {
                        context.read<ScreenEditorSensorCubit>().togglePressure();
                      },
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Units
                    AppCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Units',
                                style: AppTypography.h4(context),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                state.useMetricUnits ? 'Metric (°C, %)' : 'Imperial (°F, %)',
                                style: AppTypography.small(context),
                              ),
                            ],
                          ),
                          _ToggleSwitch(
                            enabled: state.useMetricUnits,
                            onChanged: (value) {
                              context.read<ScreenEditorSensorCubit>().toggleUnits();
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Color Configuration
                    Text(
                      'Colors',
                      style: AppTypography.h3(context),
                    ),
                    SizedBox(height: AppSpacing.md),
                    ColorPicker(
                      initialColor: state.numberColor,
                      label: 'Number Color',
                      onColorChanged: (color) {
                        context.read<ScreenEditorSensorCubit>().updateNumberColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.md),
                    ColorPicker(
                      initialColor: state.accentColor,
                      label: 'Accent Color',
                      onColorChanged: (color) {
                        context.read<ScreenEditorSensorCubit>().updateAccentColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.md),
                    ColorPicker(
                      initialColor: state.backgroundColor,
                      label: 'Background Color',
                      onColorChanged: (color) {
                        context.read<ScreenEditorSensorCubit>().updateBackgroundColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.xxl),
                    // Save Button
                    AppButton(
                      text: 'Save Configuration',
                      onPressed: () {
                        context.read<ScreenEditorSensorCubit>().save().then((_) {
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

class _SensorPreview extends StatelessWidget {
  final bool showTemperature;
  final bool showHumidity;
  final bool showPressure;
  final bool useMetricUnits;
  final Color numberColor;
  final Color accentColor;

  const _SensorPreview({
    required this.showTemperature,
    required this.showHumidity,
    required this.showPressure,
    required this.useMetricUnits,
    required this.numberColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showTemperature)
          _SensorValue(
            label: 'Temp',
            value: useMetricUnits ? '22°C' : '72°F',
            color: numberColor,
            accentColor: accentColor,
          ),
        if (showTemperature && (showHumidity || showPressure))
          SizedBox(height: AppSpacing.md),
        if (showHumidity)
          _SensorValue(
            label: 'Humidity',
            value: '45%',
            color: numberColor,
            accentColor: accentColor,
          ),
        if (showHumidity && showPressure)
          SizedBox(height: AppSpacing.md),
        if (showPressure)
          _SensorValue(
            label: 'Pressure',
            value: useMetricUnits ? '1013 hPa' : '29.9 inHg',
            color: numberColor,
            accentColor: accentColor,
          ),
      ],
    );
  }
}

class _SensorValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color accentColor;

  const _SensorValue({
    required this.label,
    required this.value,
    required this.color,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTypography.body(context).copyWith(
            color: accentColor,
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: AppTypography.h3(context).copyWith(
            color: color,
          ),
        ),
      ],
    );
  }
}

class _CheckboxOption extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckboxOption({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.h4(context),
            ),
          ),
          Checkbox(
            value: value,
            onChanged: (newValue) => onChanged(newValue ?? false),
            activeColor: AppColors.accentCyan,
          ),
        ],
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
