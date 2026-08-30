import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../models/asset_model.dart';
import '../models/screen_model.dart';
import 'screen_card.dart';

/// The device playlist, as a reorderable sliver.
///
/// This is a sliver rather than a box so the host page's own [CustomScrollView]
/// is the scrollable the drag auto-scrolls. A [ReorderableListView] shrink-
/// wrapped inside a [SingleChildScrollView] cannot auto-scroll, and the cards
/// are tall enough that a drag past the fold would otherwise be impossible.
class ScreenPlaylistSliver extends StatelessWidget {
  final List<ScreenModel> screens;
  final List<AssetModel> assets;

  /// Raw indices straight from [SliverReorderableList]; the caller is expected
  /// to apply the usual "removing shifts everything after it down one"
  /// correction. [ScreensPlaylistCubit.moveScreen] does exactly that.
  final void Function(int oldIndex, int newIndex) onReorder;

  final void Function(ScreenModel screen)? onTap;
  final void Function(ScreenModel screen)? onToggle;

  const ScreenPlaylistSliver({
    super.key,
    required this.screens,
    required this.onReorder,
    this.assets = const [],
    this.onTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: screens.length,
      onReorder: onReorder,
      proxyDecorator: _liftDraggedCard,
      itemBuilder: (context, index) {
        final screen = screens[index];

        // The key has to sit on what itemBuilder returns, not on the card
        // inside it, or the list cannot track items across a reorder.
        return Padding(
          key: ValueKey(screen.id),
          padding: EdgeInsets.only(bottom: AppSpacing.lg),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: ScreenCard(
              screen: screen,
              assets: assets,
              onTap: onTap == null ? null : () => onTap!(screen),
              onToggle: onToggle == null ? null : () => onToggle!(screen),
              dragHandle: ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  key: ValueKey('screen-drag-handle-${screen.id}'),
                  size: 22.sp,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Lifts the card being dragged off the page instead of the default
  /// Material elevation, which draws a square shadow behind the rounded card.
  Widget _liftDraggedCard(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + (0.03 * t),
          child: Opacity(opacity: 1 - (0.1 * t), child: child),
        );
      },
      child: child,
    );
  }
}
