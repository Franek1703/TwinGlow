import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/device_model.dart';
import '../../core/utils/brightness_scale.dart';
import '../../core/utils/sleep_window.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toggle.dart';
import '../../core/widgets/setting_row.dart';

/// Editor for the nightly dim window: enable flag, start/end, and the
/// brightness held during it.
///
/// Pops the edited [SleepSchedule] on save, or null when dismissed - the caller
/// only writes to Firestore on a non-null result.
class SleepModeSheet extends StatefulWidget {
  final SleepSchedule current;

  const SleepModeSheet({super.key, required this.current});

  @override
  State<SleepModeSheet> createState() => _SleepModeSheetState();
}

class _SleepModeSheetState extends State<SleepModeSheet> {
  late SleepSchedule _draft = widget.current;

  Future<void> _pickTime({required bool isStart}) async {
    final minutes = isStart ? _draft.startMinute : _draft.endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    final asMinutes = picked.hour * 60 + picked.minute;
    setState(() {
      _draft = isStart
          ? _draft.copyWith(startMinute: asMinutes)
          : _draft.copyWith(endMinute: asMinutes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sleepPercent = rawToPercent(_draft.brightness);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('Sleep mode', style: AppTypography.h4(context)),
            ),
            SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dim the display overnight',
                    style: AppTypography.body(context).copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                AppToggle(
                  enabled: _draft.enabled,
                  onChanged: (v) =>
                      setState(() => _draft = _draft.copyWith(enabled: v)),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.lg),
            SettingRow(
              label: 'Start',
              value: formatMinuteOfDay(_draft.startMinute),
              onTap: () => _pickTime(isStart: true),
            ),
            SizedBox(height: AppSpacing.md),
            SettingRow(
              label: 'End',
              value: formatMinuteOfDay(_draft.endMinute),
              onTap: () => _pickTime(isStart: false),
            ),
            SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Brightness while asleep',
                    style: AppTypography.body(context).copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                // 0 is not "very dim", it blanks the panel - brightness alone
                // cannot say that, since the firmware clamps 0 up to 1.
                Text(
                  _draft.brightness == 0 ? 'Off' : '${sleepPercent.round()}%',
                  style: AppTypography.body(context).copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Slider(
              value: sleepPercent.clamp(0, 100),
              min: 0,
              max: 100,
              activeColor: AppColors.accentPurple,
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(brightness: percentToRaw(v)),
              ),
            ),
            SizedBox(height: AppSpacing.md),
            AppButton(
              text: 'Save',
              onPressed: () => Navigator.of(context).pop(_draft),
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}
