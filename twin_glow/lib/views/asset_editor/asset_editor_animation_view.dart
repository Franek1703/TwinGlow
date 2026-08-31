import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/codecs/animation_codec.dart';
import '../../core/models/asset_model.dart';
import '../../core/widgets/animated_pixel_preview.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/color_picker.dart';
import '../../core/widgets/pixel_grid_editor.dart';
import '../../core/widgets/pixel_preview.dart';
import '../../core/widgets/tool_palette.dart';
import '../../features/asset_editor/cubit/animation_editor_cubit.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../services/firebase/firebase_repository.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class AssetEditorAnimationView extends StatefulWidget {
  final String? assetId;

  /// Frames handed over by animation import. Only ever seeds a new asset.
  final List<AnimationFrameModel>? initialFrames;

  final FirebaseRepository? repository;

  const AssetEditorAnimationView({
    super.key,
    this.assetId,
    this.initialFrames,
    this.repository,
  });

  @override
  State<AssetEditorAnimationView> createState() =>
      _AssetEditorAnimationViewState();
}

class _AssetEditorAnimationViewState extends State<AssetEditorAnimationView> {
  final _nameController = TextEditingController();
  final _tagController = TextEditingController();
  final _durationController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  String get _title =>
      widget.assetId == null ? 'Create Animation' : 'Edit Animation';

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final userId = authState.user?.id ?? '';

    if (userId.isEmpty) {
      return _scaffold(const Center(child: Text('User not authenticated')));
    }

    final firebaseRepo = widget.repository ?? FirebaseRepositoryImpl();

    return FutureBuilder<AssetModel?>(
      future: widget.assetId != null
          ? _loadAsset(firebaseRepo, widget.assetId!)
          : Future.value(null),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _scaffold(const Center(child: CircularProgressIndicator()));
        }

        return BlocProvider(
          create: (_) => AnimationEditorCubit(
            firebaseRepo,
            userId,
            asset: snapshot.data,
            initialFrames: widget.initialFrames,
          ),
          child: BlocBuilder<AnimationEditorCubit, AnimationEditorState>(
            builder: (context, state) => _buildEditor(context, state),
          ),
        );
      },
    );
  }

  Scaffold _scaffold(Widget body, {List<Widget>? actions}) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: actions,
      ),
      body: body,
    );
  }

  Widget _buildEditor(BuildContext context, AnimationEditorState state) {
    final cubit = context.read<AnimationEditorCubit>();

    if (_nameController.text.isEmpty && state.name.isNotEmpty) {
      _nameController.text = state.name;
    }
    final durationText = state.selectedFrame.durationMs.toString();
    if (_durationController.text != durationText) {
      _durationController.text = durationText;
    }

    return _scaffold(
      SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPreview(context, state),
              SizedBox(height: AppSpacing.xl),
              _buildTimeline(context, state),
              SizedBox(height: AppSpacing.xl),
              _buildDurationControl(context, state, cubit),
              SizedBox(height: AppSpacing.xl),
              Text('Pixel Editor', style: AppTypography.h2(context)),
              SizedBox(height: AppSpacing.md),
              PixelGridEditor(
                // Re-keyed whenever the frame's grid changes from outside the
                // editor, so switching frames actually reloads the canvas.
                key: ValueKey(
                  'frame-${state.selectedFrameIndex}-${state.gridRevision}',
                ),
                initialData: AnimationFrameModel.copyGrid(
                  state.selectedFrame.pixels,
                ),
                currentColor: state.currentColor,
                currentTool: state.currentTool,
                onDataChanged: cubit.updatePixelData,
              ),
              SizedBox(height: AppSpacing.lg),
              ToolPalette(
                selectedTool: state.currentTool,
                onToolSelected: cubit.setCurrentTool,
                onClear: cubit.clearGrid,
                onMirrorX: cubit.mirrorX,
                onMirrorY: cubit.mirrorY,
              ),
              SizedBox(height: AppSpacing.xl),
              ColorPicker(
                initialColor: state.currentColor,
                label: 'Current Color',
                onColorChanged: cubit.setCurrentColor,
              ),
              SizedBox(height: AppSpacing.xl),
              Text('Metadata', style: AppTypography.h2(context)),
              SizedBox(height: AppSpacing.md),
              AppInput(
                key: const Key('animation_name_field'),
                label: 'Name',
                controller: _nameController,
                hint: 'Enter animation name',
                onChanged: cubit.updateName,
              ),
              SizedBox(height: AppSpacing.lg),
              _buildTags(context, state, cubit),
              SizedBox(height: AppSpacing.xl),
              if (state.error != null) ...[
                _buildError(context, state.error!),
                SizedBox(height: AppSpacing.lg),
              ],
              AppButton(
                text: widget.assetId == null
                    ? 'Create Animation'
                    : 'Save Animation',
                onPressed: state.isLoading
                    ? null
                    : () => _saveAndClose(context),
                isLoading: state.isLoading,
                fullWidth: true,
                size: AppButtonSize.lg,
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          key: const Key('animation_save_action'),
          icon: state.isLoading
              ? SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          onPressed: state.isLoading ? null : () => _saveAndClose(context),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, AnimationEditorState state) {
    final cubit = context.read<AnimationEditorCubit>();
    return AppCard(
      child: Column(
        children: [
          Text('Preview', style: AppTypography.h4(context)),
          SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 200.h,
            child: AnimatedPixelPreview(
              frames: state.frames,
              isPlaying: state.isPlaying,
              // While paused the preview follows the frame being edited.
              pausedFrameIndex: state.selectedFrameIndex,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('animation_play_pause'),
                tooltip: state.isPlaying ? 'Pause preview' : 'Play preview',
                icon: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppColors.accentPurple,
                ),
                onPressed: cubit.togglePlayback,
              ),
              IconButton(
                key: const Key('animation_restart'),
                tooltip: 'Restart preview',
                icon: Icon(Icons.replay, color: AppColors.textMuted),
                onPressed: cubit.restartPlayback,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, AnimationEditorState state) {
    final cubit = context.read<AnimationEditorCubit>();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Frames (${state.frameCount}/${AnimationCodec.maxFrames})',
                  style: AppTypography.h4(context),
                ),
              ),
              IconButton(
                key: const Key('animation_add_frame'),
                tooltip: 'Add blank frame',
                icon: const Icon(Icons.add),
                color: AppColors.accentPurple,
                onPressed: state.canAddFrame ? cubit.addFrame : null,
              ),
              IconButton(
                key: const Key('animation_duplicate_frame'),
                tooltip: 'Duplicate frame',
                icon: const Icon(Icons.copy_all_outlined),
                color: AppColors.accentPurple,
                onPressed: state.canAddFrame
                    ? () => cubit.duplicateFrame(state.selectedFrameIndex)
                    : null,
              ),
              IconButton(
                key: const Key('animation_delete_frame'),
                tooltip: state.canDeleteFrame
                    ? 'Delete frame'
                    : 'An animation needs at least '
                          '${AnimationCodec.minFrames} frames',
                icon: const Icon(Icons.delete_outline),
                color: AppColors.statusError,
                onPressed: state.canDeleteFrame
                    ? () => cubit.deleteFrame(state.selectedFrameIndex)
                    : null,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 96.h,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: state.frameCount,
              onReorder: cubit.reorderFrames,
              itemBuilder: (context, index) {
                final isSelected = index == state.selectedFrameIndex;
                return ReorderableDragStartListener(
                  key: ValueKey('frame_tile_$index'),
                  index: index,
                  child: Padding(
                    padding: EdgeInsets.only(right: AppSpacing.sm),
                    child: GestureDetector(
                      onTap: () => cubit.selectFrame(index),
                      child: Container(
                        width: 72.w,
                        padding: EdgeInsets.all(4.w),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusLg,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accentPurple
                                : AppColors.borderSubtle,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: PixelPreview(
                                data: state.frames[index].pixels,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              '${index + 1} · ${state.frames[index].durationMs}ms',
                              style: AppTypography.small(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationControl(
    BuildContext context,
    AnimationEditorState state,
    AnimationEditorCubit cubit,
  ) {
    final error = cubit.durationError;
    final duration = state.selectedFrame.durationMs;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Frame ${state.selectedFrameIndex + 1} duration',
            style: AppTypography.h4(context),
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              IconButton(
                key: const Key('animation_duration_minus'),
                tooltip: 'Shorter by ${AnimationCodec.durationStepMs}ms',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed:
                    duration - AnimationCodec.durationStepMs >=
                        AnimationCodec.minDurationMs
                    ? () => cubit.setFrameDuration(
                        duration - AnimationCodec.durationStepMs,
                      )
                    : null,
              ),
              Expanded(
                child: AppInput(
                  key: const Key('animation_duration_field'),
                  controller: _durationController,
                  hint: 'ms',
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed != null) cubit.setFrameDuration(parsed);
                  },
                ),
              ),
              IconButton(
                key: const Key('animation_duration_plus'),
                tooltip: 'Longer by ${AnimationCodec.durationStepMs}ms',
                icon: const Icon(Icons.add_circle_outline),
                onPressed:
                    duration + AnimationCodec.durationStepMs <=
                        AnimationCodec.maxDurationMs
                    ? () => cubit.setFrameDuration(
                        duration + AnimationCodec.durationStepMs,
                      )
                    : null,
              ),
            ],
          ),
          if (error != null) ...[
            SizedBox(height: AppSpacing.sm),
            Text(
              error,
              style: AppTypography.small(
                context,
              ).copyWith(color: AppColors.statusError),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTags(
    BuildContext context,
    AnimationEditorState state,
    AnimationEditorCubit cubit,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tags', style: AppTypography.h4(context)),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppInput(
                  controller: _tagController,
                  hint: 'Add tag',
                  onChanged: (_) {},
                ),
              ),
              SizedBox(width: AppSpacing.md),
              AppButton(
                text: 'Add',
                onPressed: () {
                  if (_tagController.text.isNotEmpty) {
                    cubit.addTag(_tagController.text.trim());
                    _tagController.clear();
                  }
                },
                size: AppButtonSize.sm,
              ),
            ],
          ),
          if (state.tags.isNotEmpty) ...[
            SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: state.tags.map((tag) {
                return Chip(
                  label: Text(tag),
                  onDeleted: () => cubit.removeTag(tag),
                  backgroundColor: AppColors.bgElevated,
                  deleteIconColor: AppColors.textMuted,
                  labelStyle: AppTypography.small(context),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return AppCard(
      backgroundColor: AppColors.statusError.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.statusError, size: 20.sp),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              error,
              style: AppTypography.small(
                context,
              ).copyWith(color: AppColors.statusError),
            ),
          ),
        ],
      ),
    );
  }

  Future<AssetModel?> _loadAsset(
    FirebaseRepository repo,
    String assetId,
  ) async {
    try {
      final currentUser = await repo.getCurrentUser();
      if (currentUser == null) return null;

      final userAssets = await repo.getUserAssets(currentUser.id);
      for (final asset in userAssets) {
        if (asset.id == assetId) return asset;
      }
      final defaultAssets = await repo.getDefaultAssets();
      for (final asset in defaultAssets) {
        if (asset.id == assetId) return asset;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveAndClose(BuildContext context) async {
    final cubit = context.read<AnimationEditorCubit>();
    await cubit.save();
    if (context.mounted && cubit.state.error == null) {
      context.pop();
    }
  }
}
