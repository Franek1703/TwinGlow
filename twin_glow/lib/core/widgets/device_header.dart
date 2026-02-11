import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import 'app_card.dart';

class DeviceHeader extends StatelessWidget {
  final String deviceName;
  final bool isOnline;
  final bool hasSensor;
  final VoidCallback? onTap;

  const DeviceHeader({
    super.key,
    required this.deviceName,
    required this.isOnline,
    this.hasSensor = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      hoverable: true,
      child: Row(
        children: [
          // Device icon
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: 16,
              itemBuilder: (context, index) => Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
          SizedBox(width: AppSpacing.md),
          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: AppTypography.h3(context),
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(
                      isOnline ? Icons.wifi : Icons.wifi_off,
                      size: 14.sp,
                      color: isOnline ? AppColors.statusOnline : AppColors.statusOffline,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: isOnline ? AppColors.statusOnline : AppColors.statusOffline,
                      ),
                    ),
                    if (hasSensor) ...[
                      SizedBox(width: 12.w),
                      Icon(
                        Icons.device_thermostat,
                        size: 14.sp,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'BME680',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Chevron
          Icon(
            Icons.chevron_right,
            color: AppColors.textMuted,
            size: 20.sp,
          ),
        ],
      ),
    );
  }
}
