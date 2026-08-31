import 'dart:math' as math;

/// A square crop expressed against the source canvas, so the same selection
/// applies to a downscaled preview and to the full-resolution frames.
///
/// [left] and [top] are fractions of the canvas width and height; [size] is a
/// fraction of the canvas *width*, and the crop it describes is square in
/// pixels, not in normalized units.
class NormalizedCrop {
  final double left;
  final double top;
  final double size;

  const NormalizedCrop({
    required this.left,
    required this.top,
    required this.size,
  });

  /// The largest centred square the canvas allows - what the crop view opens
  /// on, and what an already-square source keeps untouched.
  factory NormalizedCrop.centered(int width, int height) {
    final shortSide = math.min(width, height);
    return NormalizedCrop(
      left: (width - shortSide) / 2 / width,
      top: (height - shortSide) / 2 / height,
      size: shortSide / width,
    );
  }

  /// The integer pixel rectangle to hand [img.copyCrop], clamped so a rounded
  /// edge can never read past the canvas.
  ({int x, int y, int size}) toRect(int width, int height) {
    final maxSize = math.min(width, height);
    final sizePx = (size * width).round().clamp(1, maxSize);
    final x = (left * width).round().clamp(0, width - sizePx);
    final y = (top * height).round().clamp(0, height - sizePx);
    return (x: x, y: y, size: sizePx);
  }
}

/// The pan/zoom state behind the crop view, kept free of Flutter so the
/// arithmetic that decides what gets imported is unit-testable.
///
/// The viewport is a square of [viewportSide] logical pixels showing a
/// [sizePx]-wide window onto the source. Zoom is relative to the largest
/// square that fits the canvas, so zoom 1 is always a legal selection.
class AnimationCropGeometry {
  final int sourceWidth;
  final int sourceHeight;
  final double zoom;
  final double leftPx;
  final double topPx;

  static const double maxZoom = 40;

  const AnimationCropGeometry._({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.zoom,
    required this.leftPx,
    required this.topPx,
  });

  factory AnimationCropGeometry.initial(int sourceWidth, int sourceHeight) {
    return AnimationCropGeometry.fromCrop(
      NormalizedCrop.centered(sourceWidth, sourceHeight),
      sourceWidth,
      sourceHeight,
    );
  }

  factory AnimationCropGeometry.fromCrop(
    NormalizedCrop crop,
    int sourceWidth,
    int sourceHeight,
  ) {
    final shortSide = math.min(sourceWidth, sourceHeight).toDouble();
    final sizePx = (crop.size * sourceWidth).clamp(1.0, shortSide);
    return AnimationCropGeometry._(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      zoom: shortSide / sizePx,
      leftPx: crop.left * sourceWidth,
      topPx: crop.top * sourceHeight,
    )._clamped();
  }

  double get shortSide => math.min(sourceWidth, sourceHeight).toDouble();

  double get sizePx => shortSide / zoom;

  /// How many logical pixels one source pixel occupies in the viewport.
  double displayScale(double viewportSide) => viewportSide / sizePx;

  double translateX(double viewportSide) =>
      -leftPx * displayScale(viewportSide);

  double translateY(double viewportSide) => -topPx * displayScale(viewportSide);

  /// Dragging the artwork right moves the window left, hence the subtraction.
  AnimationCropGeometry pan(double dx, double dy, double viewportSide) {
    final scale = displayScale(viewportSide);
    return _copy(
      leftPx: leftPx - dx / scale,
      topPx: topPx - dy / scale,
    )._clamped();
  }

  /// Zooms around a point in the viewport, so pinching keeps the pixels under
  /// the fingers where they are.
  AnimationCropGeometry zoomTo(
    double nextZoom,
    double focalX,
    double focalY,
    double viewportSide,
  ) {
    final clampedZoom = nextZoom.clamp(1.0, maxZoom);
    final anchorX = leftPx + focalX / displayScale(viewportSide);
    final anchorY = topPx + focalY / displayScale(viewportSide);

    final zoomed = _copy(zoom: clampedZoom);
    final nextScale = zoomed.displayScale(viewportSide);
    return zoomed
        ._copy(
          leftPx: anchorX - focalX / nextScale,
          topPx: anchorY - focalY / nextScale,
        )
        ._clamped();
  }

  NormalizedCrop get crop => NormalizedCrop(
    left: leftPx / sourceWidth,
    top: topPx / sourceHeight,
    size: sizePx / sourceWidth,
  );

  AnimationCropGeometry _clamped() {
    final side = sizePx;
    return _copy(
      leftPx: leftPx.clamp(0.0, math.max(0.0, sourceWidth - side)),
      topPx: topPx.clamp(0.0, math.max(0.0, sourceHeight - side)),
    );
  }

  AnimationCropGeometry _copy({double? zoom, double? leftPx, double? topPx}) {
    return AnimationCropGeometry._(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      zoom: zoom ?? this.zoom,
      leftPx: leftPx ?? this.leftPx,
      topPx: topPx ?? this.topPx,
    );
  }
}
