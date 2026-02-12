import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/screen_model.dart';
import '../../core/models/asset_model.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/asset_selector.dart';
import '../../core/widgets/pixel_preview.dart';
import '../../features/screen_editor/cubit/screen_editor_image_cubit.dart';
import '../../features/assets_library/cubit/assets_cubit.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class ScreenEditorImageView extends StatelessWidget {
  final String screenId;
  final String? deviceId;

  const ScreenEditorImageView({
    super.key,
    required this.screenId,
    this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    if (deviceId == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: const Text('Image Screen Editor'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Device ID is required')),
      );
    }

    final firebaseRepo = FirebaseRepositoryImpl();
    final authState = context.watch<AuthCubit>().state;
    final userId = authState.user?.id ?? '';

    // Try to load existing screen, or create new one
    return FutureBuilder<ScreenModel?>(
      future: _loadScreen(firebaseRepo, deviceId!, screenId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: const Text('Image Screen Editor'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final screen =
            snapshot.data ??
            ScreenModel(
              id: screenId,
              type: ScreenType.image,
              name: 'Image Screen',
              enabled: true,
              isShared: false,
            );

        return MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => AssetsCubit(firebaseRepo, userId)),
            BlocProvider(
              create: (context) {
                final assetsCubit = context.read<AssetsCubit>();
                final imageAssets = assetsCubit.state.myAssets
                    .where((a) => a.type == AssetType.image)
                    .toList();
                return ScreenEditorImageCubit(
                  firebaseRepo,
                  deviceId!,
                  screen,
                  imageAssets,
                );
              },
            ),
          ],
          child: Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: const Text('Image Screen Editor'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                BlocBuilder<ScreenEditorImageCubit, ScreenEditorImageState>(
                  builder: (context, state) {
                    return IconButton(
                      icon: state.isLoading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check),
                      onPressed: state.isLoading
                          ? null
                          : () {
                              context
                                  .read<ScreenEditorImageCubit>()
                                  .save()
                                  .then((_) {
                                    context.pop();
                                  });
                            },
                    );
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: BlocBuilder<ScreenEditorImageCubit, ScreenEditorImageState>(
                  builder: (context, state) {
                    final selectedAsset = state.availableAssets.firstWhere(
                      (a) => a.id == state.selectedAssetId,
                      orElse: () => state.availableAssets.isNotEmpty
                          ? state.availableAssets.first
                          : _createDummyAsset(),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preview Section
                        AppCard(
                          child: Column(
                            children: [
                              Text('Preview', style: AppTypography.h4(context)),
                              SizedBox(height: AppSpacing.lg),
                              SizedBox(
                                width: double.infinity,
                                height: 200.h,
                                child: selectedAsset.pixelData != null
                                    ? PixelPreview(
                                        data: selectedAsset.pixelData!,
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppColors.bgElevated,
                                              AppColors.bgSecondary,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusLg,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.image,
                                          size: 48.sp,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: AppSpacing.xl),
                        // Sharing Toggle
                        AppCard(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Share with Paired User',
                                    style: AppTypography.h4(context),
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    state.isShared
                                        ? 'This screen is shared'
                                        : 'Keep this screen private',
                                    style: AppTypography.small(context),
                                  ),
                                ],
                              ),
                              _ToggleSwitch(
                                enabled: state.isShared,
                                onChanged: (value) {
                                  context
                                      .read<ScreenEditorImageCubit>()
                                      .toggleSharing();
                                },
                              ),
                            ],
                          ),
                        ),
                        if (state.isShared) ...[
                          SizedBox(height: AppSpacing.md),
                          AppCard(
                            backgroundColor: AppColors.accentMagenta
                                .withOpacity(0.1),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: AppColors.accentMagenta,
                                  size: 20.sp,
                                ),
                                SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    'Both users can modify this screen\'s content',
                                    style: AppTypography.small(
                                      context,
                                    ).copyWith(color: AppColors.accentMagenta),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: AppSpacing.xl),
                        // Asset Selection
                        Text('Select Image', style: AppTypography.h2(context)),
                        SizedBox(height: AppSpacing.md),
                        BlocBuilder<AssetsCubit, AssetsState>(
                          builder: (context, assetsState) {
                            final imageAssets = [
                              ...assetsState.myAssets,
                              ...assetsState.defaultAssets,
                            ].where((a) => a.type == AssetType.image).toList();

                            return AssetSelector(
                              assets: imageAssets,
                              selectedAssetId: state.selectedAssetId,
                              onAssetSelected: (asset) {
                                context
                                    .read<ScreenEditorImageCubit>()
                                    .selectAsset(asset.id);
                              },
                            );
                          },
                        ),
                        SizedBox(height: AppSpacing.xxl),
                        // Save Button
                        AppButton(
                          text: 'Save Configuration',
                          onPressed: () {
                            context.read<ScreenEditorImageCubit>().save().then((
                              _,
                            ) {
                              context.pop();
                            });
                          },
                          fullWidth: true,
                          size: AppButtonSize.lg,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<ScreenModel?> _loadScreen(
    FirebaseRepositoryImpl repo,
    String deviceId,
    String screenId,
  ) async {
    try {
      final screens = await repo.getScreens(deviceId);
      try {
        return screens.firstWhere((s) => s.id == screenId);
      } catch (e) {
        return null; // Screen doesn't exist yet
      }
    } catch (e) {
      return null;
    }
  }

  AssetModel _createDummyAsset() {
    return AssetModel(id: 'dummy', name: 'No Asset', type: AssetType.image);
  }
}

class _ToggleSwitch extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleSwitch({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
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
      ),
    );
  }
}
