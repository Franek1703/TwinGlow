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
import '../../core/models/device_model.dart';
import '../../features/device/cubit/devices_cubit.dart';
import '../../services/firebase/firebase_fake_repository.dart';

class DeviceConfigView extends StatefulWidget {
  final String deviceId;

  const DeviceConfigView({super.key, required this.deviceId});

  @override
  State<DeviceConfigView> createState() => _DeviceConfigViewState();
}

class _DeviceConfigViewState extends State<DeviceConfigView> {
  final _nameController = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Get userId from AuthCubit
    const userId = 'user1';
    final firebaseRepo = FirebaseFakeRepository();

    return BlocProvider(
      create: (_) {
        final cubit = DevicesCubit(firebaseRepo, userId);
        cubit.loadDevices();
        return cubit;
      },
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: const Text('Device Configuration'),
        ),
        body: SafeArea(
          child: BlocBuilder<DevicesCubit, DevicesState>(
            builder: (context, state) {
              final device = state.devices.firstWhere(
                (d) => d.id == widget.deviceId,
                orElse: () => state.devices.isNotEmpty ? state.devices.first : _createDummyDevice(),
              );

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

  DeviceModel _createDummyDevice() {
    return DeviceModel(
      id: widget.deviceId,
      name: 'Unknown Device',
      isOnline: false,
      hasSensor: false,
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
