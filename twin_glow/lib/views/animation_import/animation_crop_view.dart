import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../services/animation_import/animation_crop.dart';

/// Square crop over the first composed frame of an animation.
///
/// Image import hands cropping to `image_cropper`, which returns a cropped
/// bitmap. That is no use here: the same rectangle has to be applied to every
/// frame at full resolution, so this screen returns the rectangle itself and
/// the converter does the cropping.
class AnimationCropView extends StatefulWidget {
  final Uint8List previewPng;
  final int sourceWidth;
  final int sourceHeight;
  final NormalizedCrop? initialCrop;

  const AnimationCropView({
    super.key,
    required this.previewPng,
    required this.sourceWidth,
    required this.sourceHeight,
    this.initialCrop,
  });

  @override
  State<AnimationCropView> createState() => _AnimationCropViewState();
}

class _AnimationCropViewState extends State<AnimationCropView> {
  late AnimationCropGeometry _geometry;

  double _viewportSide = 1;
  late double _zoomAtGestureStart;
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    _geometry = widget.initialCrop != null
        ? AnimationCropGeometry.fromCrop(
            widget.initialCrop!,
            widget.sourceWidth,
            widget.sourceHeight,
          )
        : AnimationCropGeometry.initial(
            widget.sourceWidth,
            widget.sourceHeight,
          );
    _zoomAtGestureStart = _geometry.zoom;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtGestureStart = _geometry.zoom;
    _lastFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final previousFocal = _lastFocalPoint ?? details.localFocalPoint;
    _lastFocalPoint = details.localFocalPoint;

    setState(() {
      // Pan first, so a two-finger gesture that also drags tracks the fingers.
      final panned = _geometry.pan(
        details.localFocalPoint.dx - previousFocal.dx,
        details.localFocalPoint.dy - previousFocal.dy,
        _viewportSide,
      );
      _geometry = details.scale == 1.0
          ? panned
          : panned.zoomTo(
              _zoomAtGestureStart * details.scale,
              details.localFocalPoint.dx,
              details.localFocalPoint.dy,
              _viewportSide,
            );
    });
  }

  void _reset() {
    setState(() {
      _geometry = AnimationCropGeometry.initial(
        widget.sourceWidth,
        widget.sourceHeight,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Crop Animation'),
        leading: IconButton(
          key: const Key('animation_crop_cancel'),
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            key: const Key('animation_crop_reset'),
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset',
            onPressed: _reset,
          ),
          IconButton(
            key: const Key('animation_crop_done'),
            icon: const Icon(Icons.check),
            tooltip: 'Done',
            onPressed: () => context.pop(_geometry.crop),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Text(
                'Drag to move, pinch to zoom. The square is what every frame '
                'is cropped to.',
                style: AppTypography.small(context),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.biggest.shortestSide;
                      _viewportSide = side;
                      return SizedBox(
                        width: side,
                        height: side,
                        child: GestureDetector(
                          key: const Key('animation_crop_surface'),
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          child: _CropViewport(
                            previewPng: widget.previewPng,
                            geometry: _geometry,
                            viewportSide: side,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Row(
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
                      text: 'Use Crop',
                      onPressed: () => context.pop(_geometry.crop),
                      fullWidth: true,
                      icon: Icon(Icons.check, size: 20.sp, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropViewport extends StatelessWidget {
  final Uint8List previewPng;
  final AnimationCropGeometry geometry;
  final double viewportSide;

  const _CropViewport({
    required this.previewPng,
    required this.geometry,
    required this.viewportSide,
  });

  @override
  Widget build(BuildContext context) {
    final scale = geometry.displayScale(viewportSide);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: AppColors.accentCyan, width: 2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(
            offset: Offset(
              geometry.translateX(viewportSide),
              geometry.translateY(viewportSide),
            ),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: SizedBox(
                  width: geometry.sourceWidth.toDouble(),
                  height: geometry.sourceHeight.toDouble(),
                  child: Image.memory(
                    previewPng,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(child: CustomPaint(painter: _CropGridPainter())),
        ],
      ),
    );
  }
}

/// Rule-of-thirds guides, matching what the still-image cropper shows.
class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(_CropGridPainter oldDelegate) => false;
}
