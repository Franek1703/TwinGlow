import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/asset_model.dart';
import '../../core/models/screen_model.dart';
import 'app_card.dart';
import 'screen_preview.dart';

class ScreenCard extends StatelessWidget {
  final ScreenModel screen;
  final List<AssetModel> assets;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  /// Grip shown between the screen name and the toggle. Supplied by the
  /// playlist, which wraps it in a drag listener; null everywhere the card is
  /// not reorderable.
  final Widget? dragHandle;

  const ScreenCard({
    super.key,
    required this.screen,
    this.assets = const [],
    this.onTap,
    this.onToggle,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      hoverable: true,
      child: Stack(
        children: [
          Column(
            children: [
              // Preview section
              SizedBox(
                width: double.infinity,
                height: 200.w,
                child: ScreenPreview(screen: screen, assets: assets),
              ),
              SizedBox(height: AppSpacing.lg),
              // Screen info
              Row(
                children: [
                  Icon(
                    _getTypeIcon(screen.type),
                    size: 18.sp,
                    color: AppColors.accentCyan,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          screen.displayName,
                          style: AppTypography.h4(context),
                        ),
                      ],
                    ),
                  ),
                  if (dragHandle != null) ...[
                    dragHandle!,
                    SizedBox(width: AppSpacing.sm),
                  ],
                  // Toggle switch
                  GestureDetector(
                    onTap: onToggle != null
                        ? () {
                            onToggle!();
                          }
                        : null,
                    child: _ToggleSwitch(enabled: screen.enabled),
                  ),
                ],
              ),
            ],
          ),
          // Shared indicator (top-right)
          if (screen.isShared &&
              (screen.type == ScreenType.image ||
                  screen.type == ScreenType.animation ||
                  screen.type == ScreenType.game))
            Positioned(
              top: AppSpacing.lg,
              right: AppSpacing.lg,
              child: Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                  color: AppColors.accentMagenta,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.link,
                  size: 14.sp,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(ScreenType type) {
    switch (type) {
      case ScreenType.clock:
        return Icons.access_time;
      case ScreenType.image:
        return Icons.image;
      case ScreenType.animation:
        return Icons.movie;
      case ScreenType.sensor:
        return Icons.device_thermostat;
      case ScreenType.game:
        return Icons.sports_esports;
    }
  }
}

class _ToggleSwitch extends StatelessWidget {
  final bool enabled;

  const _ToggleSwitch({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
    );
  }
}
