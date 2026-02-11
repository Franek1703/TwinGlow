import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/asset_model.dart';
import 'app_card.dart';
import 'pixel_preview.dart';

class AssetSelector extends StatelessWidget {
  final List<AssetModel> assets;
  final String? selectedAssetId;
  final ValueChanged<AssetModel> onAssetSelected;

  const AssetSelector({
    super.key,
    required this.assets,
    this.selectedAssetId,
    required this.onAssetSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Icon(
                  Icons.image_not_supported,
                  size: 48.sp,
                  color: AppColors.textMuted,
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  'No assets available',
                  style: AppTypography.body(context),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.9,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        final isSelected = asset.id == selectedAssetId;

        return GestureDetector(
          onTap: () => onAssetSelected(asset),
          child: AppCard(
            padding: EdgeInsets.all(AppSpacing.sm),
            backgroundColor: isSelected
                ? AppColors.accentCyan.withOpacity(0.1)
                : null,
            child: Column(
              children: [
                Expanded(
                  child: asset.pixelData != null
                      ? PixelPreview(data: asset.pixelData!)
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.bgElevated,
                                AppColors.bgSecondary,
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusLg),
                          ),
                          child: Icon(
                            asset.type == AssetType.image
                                ? Icons.image
                                : Icons.movie,
                            size: 32.sp,
                            color: AppColors.textMuted,
                          ),
                        ),
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  asset.name,
                  style: AppTypography.small(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (isSelected)
                  Container(
                    margin: EdgeInsets.only(top: 4.h),
                    width: 8.w,
                    height: 8.w,
                    decoration: BoxDecoration(
                      color: AppColors.accentCyan,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
