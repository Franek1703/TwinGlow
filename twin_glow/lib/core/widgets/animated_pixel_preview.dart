import 'dart:async';

import 'package:flutter/material.dart';
import '../models/asset_model.dart';
import 'pixel_preview.dart';

/// Plays a frame animation on a 16x16 preview.
///
/// Playback mirrors the device: frame 0 is on screen immediately, each frame's
/// duration is how long it stays visible, and the last frame returns to frame
/// 0. Animations always loop - there is no loop control anywhere in the app.
class AnimatedPixelPreview extends StatefulWidget {
  final List<AnimationFrameModel> frames;

  /// When false the preview holds on [pausedFrameIndex] (or frame 0).
  final bool isPlaying;

  /// Frame to show while paused, so the preview can follow the frame being
  /// edited rather than snapping back to the start.
  final int? pausedFrameIndex;

  /// Changing this restarts playback from frame 0.
  final Object? restartToken;

  const AnimatedPixelPreview({
    super.key,
    required this.frames,
    this.isPlaying = true,
    this.pausedFrameIndex,
    this.restartToken,
  });

  @override
  State<AnimatedPixelPreview> createState() => _AnimatedPixelPreviewState();
}

class _AnimatedPixelPreviewState extends State<AnimatedPixelPreview> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(AnimatedPixelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Swapping the asset, or an explicit restart, always returns to frame 0.
    final framesChanged = widget.frames.length != oldWidget.frames.length;
    if (framesChanged || widget.restartToken != oldWidget.restartToken) {
      _restart();
      return;
    }

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _schedule();
      } else {
        _timer?.cancel();
        _timer = null;
      }
    }

    if (!widget.isPlaying &&
        widget.pausedFrameIndex != oldWidget.pausedFrameIndex) {
      setState(() => _index = _clampIndex(widget.pausedFrameIndex ?? 0));
    }
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    _index = widget.isPlaying ? 0 : _clampIndex(widget.pausedFrameIndex ?? 0);
    if (widget.isPlaying) _schedule();
  }

  int _clampIndex(int index) {
    if (widget.frames.isEmpty) return 0;
    if (index < 0) return 0;
    if (index >= widget.frames.length) return widget.frames.length - 1;
    return index;
  }

  void _schedule() {
    _timer?.cancel();
    if (!widget.isPlaying || widget.frames.length < 2) return;

    final duration = Duration(
      milliseconds: widget.frames[_clampIndex(_index)].durationMs,
    );
    _timer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.frames.length;
      });
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) {
      return PixelPreview(data: AnimationFrameModel.emptyGrid());
    }
    return PixelPreview(data: widget.frames[_clampIndex(_index)].pixels);
  }
}
