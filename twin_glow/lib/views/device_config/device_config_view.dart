import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/device_header.dart';
import '../../core/widgets/setting_row.dart';
import 'sleep_mode_sheet.dart';
import '../../core/models/device_model.dart';
import '../../core/utils/brightness_scale.dart';
import '../../core/utils/posix_timezones.dart';
import '../../core/utils/sleep_window.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/device/cubit/devices_cubit.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class DeviceConfigView extends StatefulWidget {
  final String deviceId;

  const DeviceConfigView({super.key, required this.deviceId});

  @override
  State<DeviceConfigView> createState() => _DeviceConfigViewState();
}

class _DeviceConfigViewState extends State<DeviceConfigView> {
  final _nameController = TextEditingController();
  bool _isEditing = false;

  /// Live slider position while dragging. The write only happens on release
  /// (see [_commitBrightness]), so this holds the value the label shows in
  /// between - the device document is not updated on every frame.
  double? _brightnessPercent;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthCubit>().state.user?.id ?? '';
    final firebaseRepo = FirebaseRepositoryImpl();

    if (userId.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return BlocProvider(
      key: ValueKey(userId),
      create: (_) => DevicesCubit(firebaseRepo, userId),
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: const Text('Device Configuration'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: BlocBuilder<DevicesCubit, DevicesState>(
            builder: (context, state) {
              if (state.isInitialLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final matchingDevices =
                  state.devices.where((d) => d.id == widget.deviceId).toList();
              if (matchingDevices.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.error != null
                            ? 'Couldn\'t load device'
                            : 'Device not found',
                        style: AppTypography.body(context),
                      ),
                      if (state.error != null) ...[
                        SizedBox(height: AppSpacing.md),
                        AppButton(
                          text: 'Retry',
                          onPressed: () =>
                              context.read<DevicesCubit>().loadDevices(),
                        ),
                      ],
                    ],
                  ),
                );
              }
              final device = matchingDevices.first;

              if (!_isEditing && _nameController.text.isEmpty) {
                _nameController.text = device.name;
              }

              return SingleChildScrollView(
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
                      onTap: null,
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Device Name
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Device Name',
                                style: AppTypography.h4(context),
                              ),
                              if (!_isEditing)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isEditing = true;
                                    });
                                  },
                                  child: Text(
                                    'Edit',
                                    style: TextStyle(
                                      color: AppColors.accentCyan,
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: AppSpacing.md),
                          if (_isEditing)
                            Column(
                              children: [
                                AppInput(
                                  controller: _nameController,
                                  hint: 'Enter device name',
                                ),
                                SizedBox(height: AppSpacing.md),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = false;
                                          _nameController.text = device.name;
                                        });
                                      },
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 14.sp,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: AppSpacing.md),
                                    AppButton(
                                      text: 'Save',
                                      onPressed: () {
                                        context.read<DevicesCubit>().updateDevice(
                                          device.copyWith(name: _nameController.text),
                                        );
                                        setState(() {
                                          _isEditing = false;
                                        });
                                      },
                                      size: AppButtonSize.sm,
                                    ),
                                  ],
                                ),
                              ],
                            )
                          else
                            Text(
                              device.name,
                              style: AppTypography.body(context),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Device Info
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device Information',
                            style: AppTypography.h4(context),
                          ),
                          SizedBox(height: AppSpacing.md),
                          _InfoRow(
                            label: 'Device ID',
                            value: device.id,
                          ),
                          SizedBox(height: AppSpacing.sm),
                          _InfoRow(
                            label: 'Status',
                            value: device.isOnline ? 'Online' : 'Offline',
                            valueColor: device.isOnline
                                ? AppColors.statusOnline
                                : AppColors.statusOffline,
                          ),
                          SizedBox(height: AppSpacing.sm),
                          _InfoRow(
                            label: 'Hardware',
                            value: device.hasSensor ? 'BME680 Sensor' : 'Standard',
                          ),
                          SizedBox(height: AppSpacing.sm),
                          _TimeZoneRow(
                            value: device.timezone ?? 'Not set',
                            // The builder's context, not the State's: the
                            // DevicesCubit is provided below this widget.
                            onTap: () => _pickTimeZone(context, device),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Display
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Display', style: AppTypography.h4(context)),
                          SizedBox(height: AppSpacing.md),
                          _BrightnessControl(
                            percent: _brightnessPercentFor(device),
                            onChanged: (v) =>
                                setState(() => _brightnessPercent = v),
                            onChangeEnd: (v) =>
                                _commitBrightness(context, device, v),
                          ),
                          SizedBox(height: AppSpacing.md),
                          SettingRow(
                            label: 'Sleep mode',
                            value: _sleepSummary(device.sleepMode),
                            onTap: () => _pickSleepMode(context, device),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Remove Device Button
                    AppButton(
                      text: 'Remove Device',
                      onPressed: () {
                        // TODO: Show confirmation dialog and remove device
                      },
                      variant: AppButtonVariant.danger,
                      fullWidth: true,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pickTimeZone(BuildContext context, DeviceModel device) async {
    final cubit = context.read<DevicesCubit>();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (_) => _TimeZonePickerSheet(current: device.timezone),
    );
    if (selected == null) return;

    cubit.updateDevice(device.copyWith(
      timezone: selected,
      // Every pickable name is in the table, so the fallback never fires; UTC0
      // is simply the honest answer if one ever slipped through.
      tzPosix: posixTzFor(selected, Duration.zero),
    ));
  }

  /// The dragged value while the finger is down, otherwise whatever the device
  /// document holds.
  double _brightnessPercentFor(DeviceModel device) {
    return _brightnessPercent ??
        rawToPercent(device.brightness ?? kDefaultBrightness);
  }

  void _commitBrightness(
    BuildContext context,
    DeviceModel device,
    double percent,
  ) {
    setState(() => _brightnessPercent = percent);
    context
        .read<DevicesCubit>()
        .updateDevice(device.copyWith(brightness: percentToRaw(percent)));
  }

  String _sleepSummary(SleepSchedule? sleep) {
    if (sleep == null || !sleep.enabled) return 'Disabled';
    return '${formatMinuteOfDay(sleep.startMinute)}'
        ' - ${formatMinuteOfDay(sleep.endMinute)}';
  }

  Future<void> _pickSleepMode(BuildContext context, DeviceModel device) async {
    final cubit = context.read<DevicesCubit>();
    final updated = await showModalBottomSheet<SleepSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (_) => SleepModeSheet(
        current: device.sleepMode ?? const SleepSchedule(),
      ),
    );
    if (updated == null) return;

    cubit.updateDevice(device.copyWith(sleepMode: updated));
  }
}

/// Like [_InfoRow] but tappable, for the one row that opens a picker.
class _TimeZoneRow extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const _TimeZoneRow({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Time zone',
            style: AppTypography.body(context).copyWith(
              color: AppColors.textMuted,
            ),
          ),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTypography.body(context).copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18.sp,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable list of IANA zone names. Returns the chosen name, or null.
class _TimeZonePickerSheet extends StatefulWidget {
  final String? current;

  const _TimeZonePickerSheet({this.current});

  @override
  State<_TimeZonePickerSheet> createState() => _TimeZonePickerSheetState();
}

class _TimeZonePickerSheetState extends State<_TimeZonePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    // Matching on the name with underscores as spaces, so "new york" finds
    // America/New_York.
    final needle = _query.trim().toLowerCase();
    final zones = needle.isEmpty
        ? kPickableTimeZones
        : kPickableTimeZones
            .where((z) => z.replaceAll('_', ' ').toLowerCase().contains(needle))
            .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Text('Select time zone', style: AppTypography.h4(context)),
                  SizedBox(height: AppSpacing.md),
                  AppInput(
                    hint: 'Search, e.g. Warsaw',
                    icon: Icon(
                      Icons.search,
                      size: 18.sp,
                      color: AppColors.textMuted,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: zones.isEmpty
                  ? Center(
                      child: Text(
                        'No time zone matches "$_query"',
                        style: AppTypography.body(context).copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: zones.length,
                      itemBuilder: (context, i) {
                        final zone = zones[i];
                        final selected = zone == widget.current;
                        return ListTile(
                          title: Text(
                            zone.replaceAll('_', ' '),
                            style: AppTypography.body(context).copyWith(
                              color: selected
                                  ? AppColors.accentCyan
                                  : AppColors.textPrimary,
                            ),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check,
                                  size: 18.sp,
                                  color: AppColors.accentCyan,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(zone),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.body(context).copyWith(
            color: AppColors.textMuted,
          ),
        ),
        Text(
          value,
          style: AppTypography.body(context).copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Brightness label plus slider. The write is deferred to [onChangeEnd] so a
/// drag does not bump configVersion once per frame.
class _BrightnessControl extends StatelessWidget {
  final double percent;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BrightnessControl({
    required this.percent,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.brightness_6,
              size: 20.sp,
              color: AppColors.accentCyan,
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Brightness',
                style: AppTypography.body(context).copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Text(
              '${percent.round()}%',
              style: AppTypography.body(context).copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Slider(
          value: percent.clamp(kMinBrightnessPercent, 100),
          min: kMinBrightnessPercent,
          max: 100,
          activeColor: AppColors.accentCyan,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
