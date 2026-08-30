import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/asset_model.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/pixel_preview.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/assets_library/cubit/assets_cubit.dart';
import '../../services/firebase/firebase_repository.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class AssetsView extends StatefulWidget {
  final FirebaseRepository? repository;

  const AssetsView({super.key, this.repository});

  @override
  State<AssetsView> createState() => _AssetsViewState();
}

class _AssetsViewState extends State<AssetsView> {
  bool _isMyAssets = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final userId = authState.user?.id ?? '';
        
        if (userId.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (authState.isLoading)
                    const CircularProgressIndicator()
                  else
                    Column(
                      children: [
                        Text(
                          'Not authenticated',
                          style: AppTypography.h2(context),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        AppButton(
                          text: 'Sign In',
                          onPressed: () => context.push('/auth'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }

        return BlocProvider(
          key: ValueKey(userId),
          create: (_) => AssetsCubit(
            widget.repository ?? FirebaseRepositoryImpl(),
            userId,
          ),
          child: Builder(
            builder: (context) => Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Assets',
                  style: AppTypography.h1(context),
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Manage your images and animations',
                  style: AppTypography.body(context),
                ),
                SizedBox(height: AppSpacing.xl),
                // Tabs
                Container(
                  padding: EdgeInsets.all(4.w),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabButton(
                          text: 'My Assets',
                          isActive: _isMyAssets,
                          onTap: () => setState(() => _isMyAssets = true),
                        ),
                      ),
                      Expanded(
                        child: _TabButton(
                          text: 'Default Assets',
                          isActive: !_isMyAssets,
                          onTap: () => setState(() => _isMyAssets = false),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.xl),
                // Asset Grid
                BlocBuilder<AssetsCubit, AssetsState>(
                  builder: (context, state) {
                    final assets = _isMyAssets
                        ? state.myAssets
                        : state.defaultAssets;

                    if (state.isInitialLoading) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    return Column(
                      children: [
                        if (state.isRefreshing) ...[
                          const LinearProgressIndicator(),
                          SizedBox(height: AppSpacing.lg),
                        ],
                        if (assets.isEmpty && state.error != null)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.xl,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Couldn\'t load assets',
                                  style: AppTypography.body(context),
                                ),
                                TextButton(
                                  onPressed: () => context
                                      .read<AssetsCubit>()
                                      .loadAssets(),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        else if (assets.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.xl,
                            ),
                            child: Text(
                              _isMyAssets
                                  ? 'No assets yet'
                                  : 'No default assets available',
                              style: AppTypography.body(context),
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: AppSpacing.lg,
                              mainAxisSpacing: AppSpacing.lg,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: assets.length,
                            itemBuilder: (context, index) {
                              final asset = assets[index];
                              return AppCard(
                          onTap: () => _openAndRefresh(
                            context,
                            '/asset/edit/${asset.id}'
                            '?type=${asset.type.name}',
                          ),
                          hoverable: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.bgElevated,
                                        AppColors.bgSecondary,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(AppSpacing.radiusLg),
                                    border: Border.all(
                                      color: AppColors.borderSubtle,
                                    ),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (asset.previewPixelData != null)
                                        PixelPreview(
                                          data: asset.previewPixelData!,
                                        )
                                      else
                                        Icon(
                                          _getAssetIcon(asset.type),
                                          size: 48.sp,
                                          color: AppColors.textMuted,
                                        ),
                                      if (asset.type == AssetType.animation)
                                        Positioned(
                                          right: AppSpacing.sm,
                                          bottom: AppSpacing.sm,
                                          child: Container(
                                            padding: EdgeInsets.all(5.w),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.7,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.play_arrow,
                                              size: 16.sp,
                                              color: AppColors.accentPurple,
                                            ),
                                          ),
                                        ),
                                      if (_isMyAssets && !asset.isDefault)
                                        Positioned(
                                          top: AppSpacing.sm,
                                          right: AppSpacing.sm,
                                          child: Material(
                                            color: Colors.black.withValues(
                                              alpha: 0.72,
                                            ),
                                            shape: const CircleBorder(),
                                            child: IconButton(
                                              tooltip: 'Delete asset',
                                              onPressed: state.deletingAssetIds
                                                      .contains(asset.id)
                                                  ? null
                                                  : () => _confirmDeleteAsset(
                                                        context,
                                                        asset,
                                                      ),
                                              icon: state.deletingAssetIds
                                                      .contains(asset.id)
                                                  ? SizedBox(
                                                      width: 18.sp,
                                                      height: 18.sp,
                                                      child:
                                                          const CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons.delete_outline,
                                                      size: 20.sp,
                                                      color:
                                                          AppColors.statusError,
                                                    ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: AppSpacing.md),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      asset.name,
                                      style: AppTypography.h4(context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (asset.type == AssetType.animation)
                                    Icon(
                                      Icons.movie,
                                      size: 14.sp,
                                      color: AppColors.accentPurple,
                                    ),
                                ],
                              ),
                              SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: 4.w,
                                runSpacing: 4.h,
                                children: asset.tags
                                    .take(2)
                                    .map((tag) => Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8.w,
                                            vertical: 4.h,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.bgElevated,
                                            borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusMd,
                                            ),
                                          ),
                                          child: Text(
                                            tag,
                                            style: AppTypography.xs(context),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
                SizedBox(height: AppSpacing.xl),
                // Create buttons (only for My Assets)
                if (_isMyAssets)
                  Column(
                    children: [
                      AppButton(
                        text: 'Create New Image',
                        onPressed: () => _openAndRefresh(
                          context,
                          '/asset/create/image',
                        ),
                        fullWidth: true,
                        icon: Icon(
                          Icons.add,
                          size: 20.sp,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: AppSpacing.md),
                      AppButton(
                        text: 'Import Image',
                        onPressed: () => _openAndRefresh(
                          context,
                          '/asset/import/image',
                        ),
                        variant: AppButtonVariant.secondary,
                        fullWidth: true,
                        icon: Icon(
                          Icons.file_upload_outlined,
                          size: 20.sp,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.md),
                      AppButton(
                        text: 'Create New Animation',
                        onPressed: () => _openAndRefresh(
                          context,
                          '/asset/create/animation',
                        ),
                        variant: AppButtonVariant.secondary,
                        fullWidth: true,
                        icon: Icon(
                          Icons.add,
                          size: 20.sp,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: 100.h), // Space for bottom nav
              ],
            ),
          ),
        ),
      ),
          ),
        );
      },
    );
  }

  Future<void> _openAndRefresh(BuildContext context, String location) async {
    final assetsCubit = context.read<AssetsCubit>();
    await context.push(location);
    if (!assetsCubit.isClosed) {
      await assetsCubit.loadAssets();
    }
  }

  Future<void> _confirmDeleteAsset(
    BuildContext context,
    AssetModel asset,
  ) async {
    final assetsCubit = context.read<AssetsCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text(
          'Delete "${asset.name}"? It will also be removed from every '
          'screen that uses it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final deleted = await assetsCubit.deleteAsset(asset.id);
    if (!context.mounted) return;

    final message = deleted
        ? 'Asset deleted'
        : assetsCubit.state.error ?? 'Could not delete asset';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  IconData _getAssetIcon(AssetType type) {
    switch (type) {
      case AssetType.image:
        return Icons.image;
      case AssetType.animation:
        return Icons.movie;
    }
  }
}

class _TabButton extends StatelessWidget {
  final String text;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.text,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: 10.h,
        ),
        decoration: BoxDecoration(
          gradient: isActive ? AppColors.primaryGradient : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.button(context).copyWith(
            color: isActive ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
