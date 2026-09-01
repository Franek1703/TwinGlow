import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/asset_model.dart';
import '../../core/widgets/animated_pixel_preview.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../features/animation_import/cubit/animation_import_cubit.dart';
import '../../services/animation_import/animation_crop.dart';
import '../../services/animation_import/animation_frame_timeline.dart';
import '../../services/animation_import/animation_import_service.dart';
import '../../services/image_import/editor_image_converter.dart';
import '../../services/image_import/image_import_service.dart';
import 'animation_crop_view.dart';

class ImportAnimationView extends StatefulWidget {
  final AnimationImportService? service;

  const ImportAnimationView({super.key, this.service});

  @override
  State<ImportAnimationView> createState() => _ImportAnimationViewState();
}

class _ImportAnimationViewState extends State<ImportAnimationView> {
  late final AnimationImportCubit _cubit;

  /// Guards against the crop screen being pushed twice for one
  /// `awaitingCrop`, which a rebuild between the emit and the push would
  /// otherwise do.
  bool _cropInFlight = false;

  @override
  void initState() {
    super.initState();
    _cubit = AnimationImportCubit(
      widget.service ?? LocalAnimationImportService(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chooseSource(exitOnCancel: true);
    });
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _chooseSource({required bool exitOnCancel}) async {
    final source = await showModalBottomSheet<ImageImportSource>(
      context: context,
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (_) => const _AnimationSourceSheet(),
    );
    if (!mounted) return;
    if (source == null) {
      if (exitOnCancel) context.pop();
      return;
    }
    await _cubit.start(source);
  }

  Future<void> _openCrop(AnimationImportState state) async {
    final preview = state.preview;
    if (preview == null || _cropInFlight) return;
    _cropInFlight = true;

    final crop = await Navigator.of(context).push<NormalizedCrop>(
      MaterialPageRoute(
        builder: (_) => AnimationCropView(
          previewPng: preview.previewPng,
          sourceWidth: preview.sourceWidth,
          sourceHeight: preview.sourceHeight,
          initialCrop: state.crop,
        ),
      ),
    );
    _cropInFlight = false;
    if (!mounted) return;

    if (crop == null) {
      _cubit.cancelCrop();
      return;
    }
    await _cubit.applyCrop(crop);
  }

  Future<void> _useAnimation(List<AnimationFrameModel> frames) async {
    final initialFrames = frames.map((frame) => frame.deepCopy()).toList();
    await context.push('/asset/create/animation', extra: initialFrames);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<AnimationImportCubit, AnimationImportState>(
        listenWhen: (previous, current) =>
            previous.status != current.status ||
            previous.error != current.error,
        listener: (context, state) {
          switch (state.status) {
            case AnimationImportStatus.cancelled:
              context.pop();
            case AnimationImportStatus.awaitingCrop:
              _openCrop(state);
            case AnimationImportStatus.ready:
              if (state.error != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.error!)));
              }
            default:
              break;
          }
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: const Text('Import Animation'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: SafeArea(child: _buildBody(context, state)),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, AnimationImportState state) {
    switch (state.status) {
      case AnimationImportStatus.idle:
      case AnimationImportStatus.selecting:
        return const _ImportProgress(message: 'Opening picker…');
      case AnimationImportStatus.decoding:
        return const _ImportProgress(message: 'Reading animation frames…');
      case AnimationImportStatus.awaitingCrop:
        return const _ImportProgress(message: 'Preparing square crop…');
      case AnimationImportStatus.converting:
        return const _ImportProgress(message: 'Converting frames to 16×16…');
      case AnimationImportStatus.failure:
        return _ImportError(
          message: state.error ?? 'The animation could not be imported.',
          onChooseAnother: () => _chooseSource(exitOnCancel: false),
          onCancel: () => context.pop(),
        );
      case AnimationImportStatus.ready:
        return _buildPreview(context, state);
      case AnimationImportStatus.cancelled:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPreview(BuildContext context, AnimationImportState state) {
    final conversion = state.conversion!;
    final timeline = conversion.timelineFor(state.mode);
    final frames = timeline.frames;

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              children: [
                Text('Preview', style: AppTypography.h4(context)),
                SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: 280.h,
                  child: AnimatedPixelPreview(
                    key: ValueKey('${state.mode}-${frames.length}'),
                    frames: frames,
                    restartToken: state.mode,
                  ),
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  '${conversion.cropSize}×${conversion.cropSize} crop → 16×16 '
                  'pixels',
                  style: AppTypography.small(context),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  '${timeline.sourceFrameCount} source frames → '
                  '${frames.length} imported · '
                  '${_formatDuration(timeline.totalDurationMs)}',
                  style: AppTypography.small(context),
                ),
              ],
            ),
          ),
          if (timeline.wasReduced || timeline.wasShortened) ...[
            SizedBox(height: AppSpacing.md),
            _OptimizationNotice(timeline: timeline),
          ],
          SizedBox(height: AppSpacing.xl),
          Text('Conversion', style: AppTypography.h2(context)),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ModeOption(
                  title: 'Pixel Art',
                  description: 'Hard edges',
                  selected: state.mode == ImageConversionMode.pixelArt,
                  suggested:
                      conversion.suggestedMode == ImageConversionMode.pixelArt,
                  onTap: () => _cubit.setMode(ImageConversionMode.pixelArt),
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ModeOption(
                  title: 'Photo',
                  description: 'Smooth detail',
                  selected: state.mode == ImageConversionMode.photo,
                  suggested:
                      conversion.suggestedMode == ImageConversionMode.photo,
                  onTap: () => _cubit.setMode(ImageConversionMode.photo),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          AppButton(
            text: 'Change Crop',
            onPressed: _cubit.changeCrop,
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            icon: Icon(Icons.crop, size: 20.sp, color: AppColors.textPrimary),
          ),
          SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancel',
                  onPressed: () => context.pop(),
                  variant: AppButtonVariant.ghost,
                  fullWidth: true,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  text: 'Use Animation',
                  onPressed: () => _useAnimation(frames),
                  fullWidth: true,
                  icon: Icon(Icons.check, size: 20.sp, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int milliseconds) {
    final seconds = milliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 2 : 1)}s';
  }
}

class _OptimizationNotice extends StatelessWidget {
  final OptimizedTimeline timeline;

  const _OptimizationNotice({required this.timeline});

  @override
  Widget build(BuildContext context) {
    final reasons = <String>[
      if (timeline.wasReduced)
        'Reduced to ${timeline.frames.length} frames to fit the editor.',
      if (timeline.wasShortened)
        'Shortened to ${(timeline.totalDurationMs / 1000).toStringAsFixed(1)}s, '
            'the longest a 16-frame animation can play.',
    ];

    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: AppColors.accentCyan, size: 20.sp),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(reasons.join(' '), style: AppTypography.small(context)),
          ),
        ],
      ),
    );
  }
}

class _AnimationSourceSheet extends StatelessWidget {
  const _AnimationSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose animation source', style: AppTypography.h3(context)),
            SizedBox(height: AppSpacing.lg),
            _SourceOption(
              icon: Icons.photo_library_outlined,
              title: 'Photo Library',
              subtitle: 'Choose an animated GIF from your gallery',
              onTap: () => context.pop(ImageImportSource.photoLibrary),
            ),
            SizedBox(height: AppSpacing.md),
            _SourceOption(
              icon: Icons.folder_open,
              title: 'Files',
              subtitle: 'Browse GIF, animated WebP, or APNG files',
              onTap: () => context.pop(ImageImportSource.files),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentCyan, size: 28.sp),
          SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.h4(context)),
                Text(subtitle, style: AppTypography.small(context)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textMuted, size: 24.sp),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  const _ModeOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.bgElevated : AppColors.bgCard,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        child: Container(
          padding: EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(
              color: selected ? AppColors.accentCyan : AppColors.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? AppColors.accentCyan
                        : AppColors.textMuted,
                    size: 20.sp,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(title, style: AppTypography.h4(context)),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xs),
              Text(description, style: AppTypography.xs(context)),
              if (suggested) ...[
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Suggested',
                  style: AppTypography.xs(context).copyWith(
                    color: AppColors.accentGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportProgress extends StatelessWidget {
  final String message;

  const _ImportProgress({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: AppSpacing.lg),
          Text(message, style: AppTypography.body(context)),
        ],
      ),
    );
  }
}

class _ImportError extends StatelessWidget {
  final String message;
  final VoidCallback onChooseAnother;
  final VoidCallback onCancel;

  const _ImportError({
    required this.message,
    required this.onChooseAnother,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: SingleChildScrollView(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.statusError,
                  size: 48.sp,
                ),
                SizedBox(height: AppSpacing.lg),
                Text(
                  'Animation import failed',
                  style: AppTypography.h3(context),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  style: AppTypography.body(context),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.xl),
                AppButton(
                  text: 'Choose Another File',
                  onPressed: onChooseAnother,
                  fullWidth: true,
                ),
                SizedBox(height: AppSpacing.md),
                AppButton(
                  text: 'Cancel',
                  onPressed: onCancel,
                  variant: AppButtonVariant.ghost,
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
