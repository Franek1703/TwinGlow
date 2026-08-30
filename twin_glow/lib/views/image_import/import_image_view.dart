import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/pixel_preview.dart';
import '../../features/image_import/cubit/image_import_cubit.dart';
import '../../services/image_import/image_import_converter.dart';
import '../../services/image_import/image_import_service.dart';

class ImportImageView extends StatefulWidget {
  final ImageImportService? service;

  const ImportImageView({super.key, this.service});

  @override
  State<ImportImageView> createState() => _ImportImageViewState();
}

class _ImportImageViewState extends State<ImportImageView> {
  late final ImageImportCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ImageImportCubit(widget.service ?? LocalImageImportService());
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
      builder: (_) => const _ImageSourceSheet(),
    );
    if (!mounted) return;
    if (source == null) {
      if (exitOnCancel) context.pop();
      return;
    }
    await _cubit.start(source);
  }

  Future<void> _useImage(List<List<int>> pixelData) async {
    final initialData = pixelData.map((row) => List<int>.from(row)).toList();
    await context.push('/asset/create/image', extra: initialData);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<ImageImportCubit, ImageImportState>(
        listenWhen: (previous, current) =>
            previous.status != current.status ||
            previous.error != current.error,
        listener: (context, state) {
          if (state.status == ImageImportStatus.cancelled) {
            context.pop();
          } else if (state.status == ImageImportStatus.ready &&
              state.error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: AppColors.bgPrimary,
            appBar: AppBar(
              title: const Text('Import Image'),
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

  Widget _buildBody(BuildContext context, ImageImportState state) {
    switch (state.status) {
      case ImageImportStatus.idle:
      case ImageImportStatus.selecting:
        return const _ImportProgress(message: 'Opening image picker…');
      case ImageImportStatus.cropping:
        return const _ImportProgress(message: 'Preparing square crop…');
      case ImageImportStatus.converting:
        return const _ImportProgress(message: 'Converting to 16×16…');
      case ImageImportStatus.failure:
        return _ImportError(
          message: state.error ?? 'The image could not be imported.',
          onChooseAnother: () => _chooseSource(exitOnCancel: false),
          onCancel: () => context.pop(),
        );
      case ImageImportStatus.ready:
        return _buildPreview(context, state);
      case ImageImportStatus.cancelled:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPreview(BuildContext context, ImageImportState state) {
    final conversion = state.conversion!;
    final pixelData = state.pixelData!;

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
                  child: PixelPreview(data: pixelData),
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  '${conversion.sourceWidth}×${conversion.sourceHeight} crop → 16×16 pixels',
                  style: AppTypography.small(context),
                ),
              ],
            ),
          ),
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
                  text: 'Use Image',
                  onPressed: () => _useImage(pixelData),
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
}

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose image source', style: AppTypography.h3(context)),
            SizedBox(height: AppSpacing.lg),
            _SourceOption(
              icon: Icons.photo_library_outlined,
              title: 'Photo Library',
              subtitle: 'Choose a photo from your gallery',
              onTap: () => context.pop(ImageImportSource.photoLibrary),
            ),
            SizedBox(height: AppSpacing.md),
            _SourceOption(
              icon: Icons.folder_open,
              title: 'Files',
              subtitle: 'Browse PNG, JPG, JPEG, or WebP files',
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
                'Image import failed',
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
                text: 'Choose Another Image',
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
    );
  }
}
