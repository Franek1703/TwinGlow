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
import '../../features/auth/cubit/auth_cubit.dart';
import '../../services/ble/ble_repository.dart';
import '../../services/ble/ble_repository_impl.dart';

class DeviceProvisioningView extends StatefulWidget {
  const DeviceProvisioningView({super.key});

  @override
  State<DeviceProvisioningView> createState() => _DeviceProvisioningViewState();
}

class _DeviceProvisioningViewState extends State<DeviceProvisioningView> {
  final BLERepository _bleRepository = BleRepositoryImpl();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  List<BLEDevice> _scannedDevices = [];
  BLEDevice? _selectedDevice;
  bool _isScanning = false;
  bool _isProvisioning = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _error = null;
      _scannedDevices = [];
    });

    try {
      await _bleRepository.requestPermissions();
      final devices = await _bleRepository.scanForDevices();
      setState(() {
        _scannedDevices = devices;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isScanning = false;
      });
    }
  }

  Future<void> _provisionDevice() async {
    if (_selectedDevice == null) {
      setState(() {
        _error = 'Please select a device';
      });
      return;
    }

    if (_ssidController.text.isEmpty) {
      setState(() {
        _error = 'Please enter Wi-Fi SSID';
      });
      return;
    }

    setState(() {
      _isProvisioning = true;
      _error = null;
      _successMessage = null;
    });

    try {
      // Get current user ID
      final authState = context.read<AuthCubit>().state;
      final userId = authState.user?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await _bleRepository.provisionDevice(
        deviceId: _selectedDevice!.id,
        ssid: _ssidController.text,
        password: _passwordController.text,
        userId: userId,
      );

      setState(() {
        _successMessage = 'Device provisioned successfully!';
        _isProvisioning = false;
      });

      // Navigate back after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.go('/home');
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isProvisioning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Device Provisioning'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Provision Device',
                style: AppTypography.h1(context),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Connect your TwinGlow device via Bluetooth',
                style: AppTypography.body(context),
              ),
              SizedBox(height: AppSpacing.xl),
              // Scan Button
              AppButton(
                text: _isScanning ? 'Scanning...' : 'Scan for Devices',
                onPressed: _isScanning ? null : _scanForDevices,
                fullWidth: true,
                icon: Icon(
                  Icons.bluetooth_searching,
                  size: 20.sp,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              // Scanned Devices List
              if (_scannedDevices.isNotEmpty) ...[
                Text(
                  'Found Devices',
                  style: AppTypography.h3(context),
                ),
                SizedBox(height: AppSpacing.md),
                ..._scannedDevices.map((device) {
                  final isSelected = _selectedDevice?.id == device.id;
                  return Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      backgroundColor: isSelected
                          ? AppColors.accentCyan.withOpacity(0.1)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedDevice = device;
                        });
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.bluetooth,
                            color: isSelected
                                ? AppColors.accentCyan
                                : AppColors.textMuted,
                            size: 24.sp,
                          ),
                          SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.name,
                                  style: AppTypography.h4(context),
                                ),
                                SizedBox(height: 2.h),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.signal_cellular_alt,
                                      size: 12.sp,
                                      color: AppColors.textMuted,
                                    ),
                                    SizedBox(width: 4.w),
                                    Text(
                                      '${device.rssi} dBm',
                                      style: AppTypography.small(context),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: AppColors.accentCyan,
                              size: 24.sp,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                SizedBox(height: AppSpacing.xl),
              ],
              // Wi-Fi Credentials
              if (_selectedDevice != null) ...[
                Text(
                  'Wi-Fi Credentials',
                  style: AppTypography.h2(context),
                ),
                SizedBox(height: AppSpacing.md),
                AppInput(
                  controller: _ssidController,
                  label: 'Network Name (SSID)',
                  hint: 'Enter Wi-Fi network name',
                ),
                SizedBox(height: AppSpacing.md),
                AppInput(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Enter Wi-Fi password',
                  obscureText: true,
                ),
                SizedBox(height: AppSpacing.xl),
                // Provision Button
                AppButton(
                  text: _isProvisioning ? 'Provisioning...' : 'Provision Device',
                  onPressed: _isProvisioning ? null : _provisionDevice,
                  fullWidth: true,
                  size: AppButtonSize.lg,
                ),
              ],
              // Error Message
              if (_error != null) ...[
                SizedBox(height: AppSpacing.lg),
                AppCard(
                  backgroundColor: AppColors.statusError.withOpacity(0.1),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: AppColors.statusError,
                        size: 20.sp,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTypography.small(context).copyWith(
                            color: AppColors.statusError,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Success Message
              if (_successMessage != null) ...[
                SizedBox(height: AppSpacing.lg),
                AppCard(
                  backgroundColor: AppColors.accentGreen.withOpacity(0.1),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.accentGreen,
                        size: 20.sp,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: AppTypography.small(context).copyWith(
                            color: AppColors.accentGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
