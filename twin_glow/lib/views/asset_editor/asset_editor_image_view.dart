import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/color_picker.dart';
import '../../core/widgets/pixel_grid_editor.dart';
import '../../core/widgets/tool_palette.dart';
import '../../core/widgets/pixel_preview.dart';
import '../../features/asset_editor/cubit/asset_editor_cubit.dart';

class AssetEditorImageView extends StatefulWidget {
  final String? assetId;

  const AssetEditorImageView({super.key, this.assetId});

  @override
  State<AssetEditorImageView> createState() => _AssetEditorImageViewState();
}

class _AssetEditorImageViewState extends State<AssetEditorImageView> {
  final _nameController = TextEditingController();
  final _tagController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Load asset from repository if assetId is provided
    return BlocProvider(
      create: (_) => AssetEditorCubit(),
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: Text(widget.assetId == null ? 'Create Image' : 'Edit Image'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          actions: [
            BlocBuilder<AssetEditorCubit, AssetEditorState>(
              builder: (context, state) {
                return IconButton(
                  icon: state.isLoading
                      ? SizedBox(
                          width: 20.w,
                          height: 20.w,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  onPressed: state.isLoading
                      ? null
                      : () {
                          context.read<AssetEditorCubit>().save().then((_) {
                            context.pop();
                          });
                        },
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: BlocBuilder<AssetEditorCubit, AssetEditorState>(
            builder: (context, state) {
              if (_nameController.text.isEmpty && state.name.isNotEmpty) {
                _nameController.text = state.name;
              }

              return SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Preview
                    AppCard(
                      child: Column(
                        children: [
                          Text(
                            'Preview',
                            style: AppTypography.h4(context),
                          ),
                          SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            height: 200.h,
                            child: PixelPreview(data: state.pixelData),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Pixel Grid Editor
                    Text(
                      'Pixel Editor',
                      style: AppTypography.h2(context),
                    ),
                    SizedBox(height: AppSpacing.md),
                    PixelGridEditor(
                      initialData: state.pixelData,
                      currentColor: state.currentColor,
                      currentTool: state.currentTool,
                      onDataChanged: (data) {
                        context.read<AssetEditorCubit>().updatePixelData(data);
                      },
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Tools
                    ToolPalette(
                      selectedTool: state.currentTool,
                      onToolSelected: (tool) {
                        context.read<AssetEditorCubit>().setCurrentTool(tool);
                      },
                      onClear: () {
                        context.read<AssetEditorCubit>().clearGrid();
                      },
                      onMirrorX: () {
                        context.read<AssetEditorCubit>().mirrorX();
                      },
                      onMirrorY: () {
                        context.read<AssetEditorCubit>().mirrorY();
                      },
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Color Picker
                    ColorPicker(
                      initialColor: state.currentColor,
                      label: 'Current Color',
                      onColorChanged: (color) {
                        context.read<AssetEditorCubit>().setCurrentColor(color);
                      },
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Metadata
                    Text(
                      'Metadata',
                      style: AppTypography.h2(context),
                    ),
                    SizedBox(height: AppSpacing.md),
                    AppInput(
                      label: 'Name',
                      controller: _nameController,
                      hint: 'Enter asset name',
                      onChanged: (value) {
                        context.read<AssetEditorCubit>().updateName(value);
                      },
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Tags
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tags',
                            style: AppTypography.h4(context),
                          ),
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
                                    context
                                        .read<AssetEditorCubit>()
                                        .addTag(_tagController.text.trim());
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
                                  onDeleted: () {
                                    context
                                        .read<AssetEditorCubit>()
                                        .removeTag(tag);
                                  },
                                  backgroundColor: AppColors.bgElevated,
                                  deleteIconColor: AppColors.textMuted,
                                  labelStyle: AppTypography.small(context),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Error Display
                    if (state.error != null)
                      AppCard(
                        backgroundColor: AppColors.statusError.withOpacity(0.1),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: AppColors.statusError,
                              size: 20.sp,
                            ),
                            SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                state.error!,
                                style: AppTypography.small(context).copyWith(
                                  color: AppColors.statusError,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (state.error != null) SizedBox(height: AppSpacing.lg),
                    // Save Button
                    AppButton(
                      text: widget.assetId == null ? 'Create Asset' : 'Save Asset',
                      onPressed: () {
                        context.read<AssetEditorCubit>().save().then((_) {
                          if (context.mounted && state.error == null) {
                            context.pop();
                          }
                        });
                      },
                      fullWidth: true,
                      size: AppButtonSize.lg,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
