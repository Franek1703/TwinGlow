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
import '../../core/widgets/screen_preview.dart';
import '../../features/screen_editor/cubit/screen_editor_image_cubit.dart';
import '../../features/assets_library/cubit/assets_cubit.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class ScreenEditorImageView extends StatelessWidget {
  final String screenId;
  final String? deviceId;
  final ScreenType screenType;

  const ScreenEditorImageView({
    super.key,
    required this.screenId,
    this.deviceId,
    this.screenType = ScreenType.image,
  });

  String get _editorTitle => screenType == ScreenType.animation
      ? 'Animation Screen Editor'
      : 'Image Screen Editor';

  @override
  Widget build(BuildContext context) {
    if (deviceId == null) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: Text(_editorTitle),
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
              title: Text(_editorTitle),
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
              type: screenType,
              name: screenType == ScreenType.animation
                  ? 'Animation Screen'
                  : 'Image Screen',
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
                    .where((a) => a.type == _assetType)
                    .toList();
                return ScreenEditorImageCubit(
                  firebaseRepo,
                  deviceId!,
                  screen,
                  imageAssets,
                  userId: userId,
                );
              },
            ),
          ],
          child: Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: Text(_editorTitle),
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
                    final assetsState = context.watch<AssetsCubit>().state;
                    final compatibleAssets = [
                      ...assetsState.myAssets,
                      ...assetsState.defaultAssets,
                    ].where((asset) => asset.type == _assetType).toList();
                    final previewScreen = ScreenModel(
                      id: state.screen.id,
                      type: screenType,
                      name: state.screen.name,
                      enabled: state.screen.enabled,
                      isShared: state.isShared,
                      previewData: state.screen.previewData,
                      assetId: state.defaultAssetId,
                      config: state.screen.config,
                      defaultAssetId: state.defaultAssetId,
                      availableAssetIds: state.poolAssetIds,
                      allowManualSwitch: state.screen.allowManualSwitch,
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
                                child: assetsState.isInitialLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : assetsState.error != null &&
                                          compatibleAssets.isEmpty
                                    ? Center(
                                        child: Text(
                                          'Couldn\'t load assets',
                                          style: AppTypography.body(context),
                                        ),
                                      )
                                    : ScreenPreview(
                                        screen: previewScreen,
                                        assets: compatibleAssets,
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
                        Text(
                          screenType == ScreenType.animation
                              ? 'Animations on this screen'
                              : 'Images on this screen',
                          style: AppTypography.h2(context),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          state.poolAssetIds.length > 1
                              ? 'Tap to add or remove. Hold to set the starting image (★). '
                                  'The device cycles them in this order with the action button.'
                              : 'Tap to add assets. Add more than one to cycle them '
                                  'with the action button on the device.',
                          style: AppTypography.small(context),
                        ),
                        SizedBox(height: AppSpacing.md),
                        if (assetsState.isInitialLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (assetsState.error != null &&
                            compatibleAssets.isEmpty)
                          Center(
                            child: TextButton(
                              onPressed: () => context
                                  .read<AssetsCubit>()
                                  .loadAssets(),
                              child: const Text('Retry loading assets'),
                            ),
                          )
                        else ...[
                          if (assetsState.isRefreshing) ...[
                            const LinearProgressIndicator(),
                            SizedBox(height: AppSpacing.md),
                          ],
                          AssetSelector(
                            assets: compatibleAssets,
                            selectedAssetId: state.selectedAssetId,
                            poolAssetIds: state.poolAssetIds,
                            defaultAssetId: state.defaultAssetId,
                            onAssetSelected: (asset) {
                              context
                                  .read<ScreenEditorImageCubit>()
                                  .selectAsset(asset.id);
                            },
                            onAssetToggled: (asset) {
                              context
                                  .read<ScreenEditorImageCubit>()
                                  .toggleAssetInPool(asset.id);
                            },
                            onSetDefault: (asset) {
                              context
                                  .read<ScreenEditorImageCubit>()
                                  .setDefaultAsset(asset.id);
                            },
                          ),
                        ],
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

  AssetType get _assetType => screenType == ScreenType.animation
      ? AssetType.animation
      : AssetType.image;
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
