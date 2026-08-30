import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }
enum AppButtonSize { sm, md, lg }

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool fullWidth;
  final Widget? icon;
  final bool isLoading;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.fullWidth = false,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;

    return Container(
      width: fullWidth ? double.infinity : null,
      height: _getHeight(),
      decoration: BoxDecoration(
        gradient: variant == AppButtonVariant.primary && isEnabled
            ? AppColors.primaryGradient
            : null,
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: variant == AppButtonVariant.secondary
            ? Border.all(color: AppColors.borderColor)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _getHorizontalPadding(),
              vertical: _getVerticalPadding(),
            ),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        icon!,
                        SizedBox(width: 8.w),
                      ],
                      // Flexible so a long label ellipsizes instead of
                      // overflowing the button. A full-width lg button is
                      // narrower than its own text once the label passes about
                      // a dozen characters.
                      Flexible(
                        child: Text(
                          text,
                          style: _getTextStyle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Color? _getBackgroundColor() {
    if (variant == AppButtonVariant.primary) return null; // Uses gradient
    if (variant == AppButtonVariant.secondary) return AppColors.bgElevated;
    if (variant == AppButtonVariant.danger) return AppColors.statusError;
    return Colors.transparent;
  }

  TextStyle _getTextStyle(BuildContext context) {
    final baseStyle = size == AppButtonSize.lg
        ? AppTypography.buttonLarge(context)
        : size == AppButtonSize.sm
            ? AppTypography.buttonSmall(context)
            : AppTypography.button(context);

    if (variant == AppButtonVariant.ghost) {
      return baseStyle.copyWith(color: AppColors.textSecondary);
    }
    return baseStyle;
  }

  double _getHeight() {
    switch (size) {
      case AppButtonSize.sm:
        return 36.h;
      case AppButtonSize.md:
        return 44.h;
      case AppButtonSize.lg:
        return 56.h;
    }
  }

  double _getHorizontalPadding() {
    switch (size) {
      case AppButtonSize.sm:
        return AppSpacing.md;
      case AppButtonSize.md:
        return AppSpacing.lg;
      case AppButtonSize.lg:
        return AppSpacing.xl;
    }
  }

  double _getVerticalPadding() {
    switch (size) {
      case AppButtonSize.sm:
        return AppSpacing.sm;
      case AppButtonSize.md:
        return AppSpacing.md;
      case AppButtonSize.lg:
        return AppSpacing.lg;
    }
  }
}
