import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../models/asset_model.dart';
import '../models/screen_model.dart';
import 'pixel_preview.dart';

/// Returns every asset referenced by [screen] in device cycle order.
///
/// Legacy screens only have [ScreenModel.assetId], while current image and
/// animation screens use [ScreenModel.availableAssetIds]. The default is also
/// included if an inconsistent/partially migrated document left it outside the
/// pool, so the in-app preview never silently hides a referenced asset.
List<String> assetIdsForScreenPreview(ScreenModel screen) {
  final ids = <String>[];

  void add(String? id) {
    if (id != null && id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }

  if (screen.availableAssetIds.isNotEmpty) {
    for (final id in screen.availableAssetIds) {
      add(id);
    }
  } else {
    add(screen.assetId);
  }

  add(screen.defaultAssetId);
  add(screen.assetId);
  return ids;
}

/// A device-like preview for every supported screen type.
///
/// Image and animation screens resolve their complete asset pool and expose it
/// as a swipeable carousel. Clock and sensor previews render their saved
/// configuration instead of a generic type icon.
class ScreenPreview extends StatefulWidget {
  final ScreenModel screen;
  final List<AssetModel> assets;

  const ScreenPreview({
    super.key,
    required this.screen,
    this.assets = const [],
  });

  @override
  State<ScreenPreview> createState() => _ScreenPreviewState();
}

class _ScreenPreviewState extends State<ScreenPreview> {
  late PageController _pageController;
  late String _carouselSignature;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _carouselSignature = _signatureFor(widget.screen);
    _pageIndex = _initialPage(widget.screen);
    _pageController = PageController(initialPage: _pageIndex);
  }

  @override
  void didUpdateWidget(covariant ScreenPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signatureFor(widget.screen);
    if (signature == _carouselSignature) return;

    _pageController.dispose();
    _carouselSignature = signature;
    _pageIndex = _initialPage(widget.screen);
    _pageController = PageController(initialPage: _pageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.screen.type) {
      case ScreenType.clock:
        return _ClockScreenPreview(config: widget.screen.config);
      case ScreenType.sensor:
        return _SensorScreenPreview(config: widget.screen.config);
      case ScreenType.image:
      case ScreenType.animation:
        return _buildAssetCarousel(context);
      case ScreenType.game:
        return const _GameScreenPreview();
    }
  }

  Widget _buildAssetCarousel(BuildContext context) {
    final ids = assetIdsForScreenPreview(widget.screen);
    final assetsById = {for (final asset in widget.assets) asset.id: asset};

    if (ids.isEmpty) {
      if (widget.screen.previewData != null) {
        return PixelPreview(data: widget.screen.previewData!);
      }
      return _EmptyPreview(type: widget.screen.type);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: Stack(
        children: [
          PageView.builder(
            key: ValueKey(_carouselSignature),
            controller: _pageController,
            itemCount: ids.length,
            onPageChanged: (index) => setState(() => _pageIndex = index),
            itemBuilder: (context, index) {
              final asset = assetsById[ids[index]];
              final fallbackData = ids.length == 1
                  ? widget.screen.previewData
                  : null;
              return _AssetPage(
                assetId: ids[index],
                asset: asset,
                fallbackData: fallbackData,
                screenType: widget.screen.type,
              );
            },
          ),
          if (ids.length > 1) ...[
            Positioned(
              left: AppSpacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CarouselButton(
                  key: const ValueKey('screen-preview-previous'),
                  icon: Icons.chevron_left,
                  label: 'Previous asset',
                  onTap: () => _goToPage((_pageIndex - 1) % ids.length),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CarouselButton(
                  key: const ValueKey('screen-preview-next'),
                  icon: Icons.chevron_right,
                  label: 'Next asset',
                  onTap: () => _goToPage((_pageIndex + 1) % ids.length),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  ids.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: index == _pageIndex ? 14.w : 6.w,
                    height: 6.w,
                    margin: EdgeInsets.symmetric(horizontal: 2.w),
                    decoration: BoxDecoration(
                      color: index == _pageIndex
                          ? AppColors.accentCyan
                          : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Container(
              key: const ValueKey('screen-preview-counter'),
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                '${_pageIndex + 1} / ${ids.length}',
                style: AppTypography.xs(
                  context,
                ).copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  static String _signatureFor(ScreenModel screen) {
    return '${screen.type.name}|${assetIdsForScreenPreview(screen).join(',')}|'
        '${screen.defaultAssetId ?? screen.assetId ?? ''}';
  }

  static int _initialPage(ScreenModel screen) {
    final ids = assetIdsForScreenPreview(screen);
    final defaultId = screen.defaultAssetId ?? screen.assetId;
    final index = defaultId == null ? -1 : ids.indexOf(defaultId);
    return index < 0 ? 0 : index;
  }
}

class _AssetPage extends StatelessWidget {
  final String assetId;
  final AssetModel? asset;
  final List<List<int>>? fallbackData;
  final ScreenType screenType;

  const _AssetPage({
    required this.assetId,
    required this.asset,
    required this.fallbackData,
    required this.screenType,
  });

  @override
  Widget build(BuildContext context) {
    final data = asset?.pixelData ?? fallbackData;
    final isAnimation =
        asset?.type == AssetType.animation ||
        screenType == ScreenType.animation;
    final name = asset?.name ?? 'Asset unavailable';

    return Semantics(
      image: true,
      label: '$name preview',
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (data != null)
            PixelPreview(data: data)
          else
            _MissingAssetPreview(assetId: assetId, isAnimation: isAnimation),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(12.w, 22.h, 12.w, 8.h),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xD9000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isAnimation ? Icons.play_circle_fill : Icons.image,
                    size: 16.sp,
                    color: isAnimation
                        ? AppColors.accentPurple
                        : AppColors.accentCyan,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.small(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CarouselButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.black.withValues(alpha: 0.62),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(5.w),
            child: Icon(icon, size: 20.sp, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _ClockScreenPreview extends StatefulWidget {
  final Map<String, dynamic>? config;

  const _ClockScreenPreview({required this.config});

  @override
  State<_ClockScreenPreview> createState() => _ClockScreenPreviewState();
}

class _ClockScreenPreviewState extends State<_ClockScreenPreview> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSeconds = widget.config?['showSeconds'] as bool? ?? true;
    final digitColor = _colorFromConfig(
      widget.config,
      'digitColor',
      AppColors.accentCyan,
    );
    final colonColor = _colorFromConfig(
      widget.config,
      'colonColor',
      AppColors.accentCyan,
    );
    final backgroundColor = _colorFromConfig(
      widget.config,
      'backgroundColor',
      Colors.black,
    );
    final parts = [
      _now.hour.toString().padLeft(2, '0'),
      _now.minute.toString().padLeft(2, '0'),
      if (showSeconds) _now.second.toString().padLeft(2, '0'),
    ];

    return _ConfiguredPreviewFrame(
      backgroundColor: backgroundColor,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < parts.length; index++) ...[
              if (index > 0)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5.w),
                  child: Text(
                    ':',
                    style: TextStyle(
                      color: colonColor,
                      fontSize: 44.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Text(
                parts[index],
                style: TextStyle(
                  color: digitColor,
                  fontSize: 44.sp,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: [
                    Shadow(
                      color: digitColor.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SensorScreenPreview extends StatelessWidget {
  final Map<String, dynamic>? config;

  const _SensorScreenPreview({required this.config});

  @override
  Widget build(BuildContext context) {
    final showTemperature = config?['showTemperature'] as bool? ?? true;
    final showHumidity = config?['showHumidity'] as bool? ?? true;
    final showPressure = config?['showPressure'] as bool? ?? false;
    final metric = config?['useMetricUnits'] as bool? ?? true;
    final numberColor = _colorFromConfig(
      config,
      'numberColor',
      AppColors.accentCyan,
    );
    final accentColor = _colorFromConfig(
      config,
      'accentColor',
      AppColors.accentGreen,
    );
    final backgroundColor = _colorFromConfig(
      config,
      'backgroundColor',
      Colors.black,
    );
    final readings = <(IconData, String, String)>[
      if (showTemperature)
        (Icons.thermostat, 'Temperature', metric ? '22°C' : '72°F'),
      if (showHumidity) (Icons.water_drop_outlined, 'Humidity', '45%'),
      if (showPressure)
        (Icons.speed, 'Pressure', metric ? '1013 hPa' : '29.9 inHg'),
    ];

    if (readings.isEmpty) {
      return _ConfiguredPreviewFrame(
        backgroundColor: backgroundColor,
        child: Text(
          'No readings selected',
          style: AppTypography.small(context),
        ),
      );
    }

    return _ConfiguredPreviewFrame(
      backgroundColor: backgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: readings.map((reading) {
          return Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(reading.$1, color: accentColor, size: 22.sp),
                  SizedBox(height: 5.h),
                  Text(
                    reading.$3,
                    style: AppTypography.h3(context).copyWith(
                      color: numberColor,
                      shadows: [
                        Shadow(
                          color: numberColor.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    reading.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.xs(
                      context,
                    ).copyWith(color: accentColor),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GameScreenPreview extends StatelessWidget {
  const _GameScreenPreview();

  @override
  Widget build(BuildContext context) {
    return _ConfiguredPreviewFrame(
      backgroundColor: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sports_esports,
            size: 58.sp,
            color: AppColors.accentPurple,
            shadows: const [
              Shadow(color: AppColors.accentPurple, blurRadius: 14),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'READY',
            style: AppTypography.h3(
              context,
            ).copyWith(color: AppColors.accentCyan, letterSpacing: 5.w),
          ),
        ],
      ),
    );
  }
}

class _ConfiguredPreviewFrame extends StatelessWidget {
  final Color backgroundColor;
  final Widget child;

  const _ConfiguredPreviewFrame({
    required this.backgroundColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _MissingAssetPreview extends StatelessWidget {
  final String assetId;
  final bool isAnimation;

  const _MissingAssetPreview({
    required this.assetId,
    required this.isAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.bgElevated, AppColors.bgSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAnimation ? Icons.movie_outlined : Icons.broken_image_outlined,
              size: 42.sp,
              color: AppColors.textMuted,
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              assetId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.xs(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  final ScreenType type;

  const _EmptyPreview({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.bgElevated, AppColors.bgSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type == ScreenType.animation ? Icons.movie : Icons.image,
              size: 42.sp,
              color: AppColors.textMuted,
            ),
            SizedBox(height: AppSpacing.sm),
            Text('No asset selected', style: AppTypography.small(context)),
          ],
        ),
      ),
    );
  }
}

Color _colorFromConfig(
  Map<String, dynamic>? config,
  String key,
  Color fallback,
) {
  final value = config?[key];
  if (value is int) return Color(value);
  if (value is String) {
    final normalized = value.replaceFirst('#', '');
    final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
    final parsed = int.tryParse(withAlpha, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}
