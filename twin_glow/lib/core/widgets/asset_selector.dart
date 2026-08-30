import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/asset_model.dart';
import 'app_card.dart';
import 'pixel_preview.dart';

/// Grid of assets.
///
/// Single-select by default. Passing [poolAssetIds] switches it to multi-select:
/// tapping toggles membership of the screen's asset pool, long-pressing marks
/// the default, and each card shows its position in the cycle order.
class AssetSelector extends StatelessWidget {
  final List<AssetModel> assets;
  final String? selectedAssetId;
  final ValueChanged<AssetModel> onAssetSelected;

  final List<String>? poolAssetIds;
  final String? defaultAssetId;
  final ValueChanged<AssetModel>? onAssetToggled;
  final ValueChanged<AssetModel>? onSetDefault;

  const AssetSelector({
    super.key,
    required this.assets,
    this.selectedAssetId,
    required this.onAssetSelected,
    this.poolAssetIds,
    this.defaultAssetId,
    this.onAssetToggled,
    this.onSetDefault,
  });

  bool get _isMultiSelect => poolAssetIds != null;

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
        final poolIndex = poolAssetIds?.indexOf(asset.id) ?? -1;
        final inPool = poolIndex != -1;
        final isDefault = _isMultiSelect && asset.id == defaultAssetId;
        final isSelected =
            _isMultiSelect ? inPool : asset.id == selectedAssetId;

        return GestureDetector(
          onTap: () => _isMultiSelect
              ? onAssetToggled?.call(asset)
              : onAssetSelected(asset),
          onLongPress:
              _isMultiSelect ? () => onSetDefault?.call(asset) : null,
          child: AppCard(
            padding: EdgeInsets.all(AppSpacing.sm),
            backgroundColor:
                isSelected ? AppColors.accentCyan.withOpacity(0.1) : null,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: asset.previewPixelData != null
                            ? PixelPreview(data: asset.previewPixelData!)
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
                      // Cycle position, so the order the device steps through
                      // the pool is visible at a glance.
                      if (inPool)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            width: 16.w,
                            height: 16.w,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.accentCyan,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${poolIndex + 1}',
                              style: AppTypography.small(context).copyWith(
                                color: AppColors.bgPrimary,
                                fontSize: 9.sp,
                              ),
                            ),
                          ),
                        ),
                      if (isDefault)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.star,
                            size: 14.sp,
                            color: AppColors.accentMagenta,
                          ),
                        ),
                    ],
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
                if (isSelected && !_isMultiSelect)
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
