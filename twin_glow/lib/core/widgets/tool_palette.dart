import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import 'pixel_grid_editor.dart';

class ToolPalette extends StatelessWidget {
  final DrawingTool selectedTool;
  final ValueChanged<DrawingTool> onToolSelected;
  final VoidCallback onClear;
  final VoidCallback onMirrorX;
  final VoidCallback onMirrorY;

  const ToolPalette({
    super.key,
    required this.selectedTool,
    required this.onToolSelected,
    required this.onClear,
    required this.onMirrorX,
    required this.onMirrorY,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tools',
            style: AppTypography.h4(context),
          ),
          SizedBox(height: AppSpacing.md),
          // Drawing Tools
          Row(
            children: [
              _ToolButton(
                icon: Icons.edit,
                label: 'Pencil',
                isSelected: selectedTool == DrawingTool.pencil,
                onTap: () => onToolSelected(DrawingTool.pencil),
              ),
              SizedBox(width: AppSpacing.sm),
              _ToolButton(
                icon: Icons.auto_fix_high,
                label: 'Eraser',
                isSelected: selectedTool == DrawingTool.eraser,
                onTap: () => onToolSelected(DrawingTool.eraser),
              ),
              SizedBox(width: AppSpacing.sm),
              _ToolButton(
                icon: Icons.format_color_fill,
                label: 'Fill',
                isSelected: selectedTool == DrawingTool.fill,
                onTap: () => onToolSelected(DrawingTool.fill),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          // Actions
          Row(
            children: [
              _ActionButton(
                icon: Icons.flip,
                label: 'Mirror X',
                onTap: onMirrorX,
              ),
              SizedBox(width: AppSpacing.sm),
              _ActionButton(
                icon: Icons.swap_vert,
                label: 'Mirror Y',
                onTap: onMirrorY,
              ),
              SizedBox(width: AppSpacing.sm),
              _ActionButton(
                icon: Icons.clear_all,
                label: 'Clear',
                onTap: onClear,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: isSelected
                ? null
                : Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24.sp,
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: AppTypography.xs(context).copyWith(
                  color: isSelected ? Colors.white : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isDestructive
                ? AppColors.statusError.withOpacity(0.1)
                : AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: isDestructive
                  ? AppColors.statusError.withOpacity(0.3)
                  : AppColors.borderSubtle,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20.sp,
                color: isDestructive
                    ? AppColors.statusError
                    : AppColors.textMuted,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: AppTypography.xs(context).copyWith(
                  color: isDestructive
                      ? AppColors.statusError
                      : AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
