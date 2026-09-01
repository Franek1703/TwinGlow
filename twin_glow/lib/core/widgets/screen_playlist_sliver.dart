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

  /// Called once the card has swiped away and the confirmation was accepted.
  /// Cards are not swipeable at all when this is null.
  final void Function(ScreenModel screen)? onDelete;

  const ScreenPlaylistSliver({
    super.key,
    required this.screens,
    required this.onReorder,
    this.assets = const [],
    this.onTap,
    this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: screens.length,
      onReorder: onReorder,
      proxyDecorator: _liftDraggedCard,
      itemBuilder: (context, index) {
        final screen = screens[index];

        // Long press to drag, so a horizontal swipe is free to mean delete.
        final card = ReorderableDelayedDragStartListener(
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
        );

        // The key has to sit on what itemBuilder returns, not on the card
        // inside it, or the list cannot track items across a reorder.
        return Padding(
          key: ValueKey(screen.id),
          padding: EdgeInsets.only(bottom: AppSpacing.lg),
          child: onDelete == null
              ? card
              : Dismissible(
                  key: ValueKey('screen-dismiss-${screen.id}'),
                  // One direction only: a two-way swipe on a card that also
                  // drags is too easy to trigger by accident.
                  direction: DismissDirection.endToStart,
                  background: _deleteBackground(),
                  confirmDismiss: (_) => _confirmDelete(context, screen),
                  onDismissed: (_) => onDelete!(screen),
                  child: card,
                ),
        );
      },
    );
  }

  /// The field revealed as the card slides away, so the gesture reads as
  /// destructive before it completes. Rounded to the card's own radius, or the
  /// corners show square red behind a rounded card mid-swipe.
  Widget _deleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.statusError,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Icon(
        Icons.delete_outline,
        size: 24.sp,
        color: AppColors.textPrimary,
      ),
    );
  }

  /// Deleting a screen also drops its shared-screen pointer and bumps the
  /// device's config version, so it is worth a confirmation step.
  Future<bool> _confirmDelete(BuildContext context, ScreenModel screen) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete screen?'),
        content: Text(
          'Delete "${screen.name}"? It is removed from the device playlist, '
          'and stops being shared with a paired device if it was.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
