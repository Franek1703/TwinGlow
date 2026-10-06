import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/codecs/animation_codec.dart';
import '../../../core/models/asset_model.dart';
import '../../../core/widgets/pixel_grid_editor.dart';
import '../../../services/firebase/firebase_repository.dart';

class AnimationEditorState {
  final AssetModel? asset;
  final List<AnimationFrameModel> frames;
  final int selectedFrameIndex;

  /// Bumped whenever the selected frame's grid changes from outside the pixel
  /// editor - a frame switch, clear, mirror, or a structural edit. The view
  /// keys [PixelGridEditor] on it so the editor re-reads the frame instead of
  /// holding the grid it captured when it was first built.
  final int gridRevision;

  final Color currentColor;
  final DrawingTool currentTool;
  final String name;
  final List<String> tags;
  final bool isPlaying;
  final bool isLoading;
  final String? error;

  const AnimationEditorState({
    this.asset,
    required this.frames,
    this.selectedFrameIndex = 0,
    this.gridRevision = 0,
    this.currentColor = const Color(0xFF00D9FF),
    this.currentTool = DrawingTool.pencil,
    this.name = '',
    this.tags = const [],
    this.isPlaying = false,
    this.isLoading = false,
    this.error,
  });

  AnimationFrameModel get selectedFrame => frames[selectedFrameIndex];

  int get frameCount => frames.length;

  bool get canDeleteFrame => frames.length > AnimationCodec.minFrames;

  bool get canAddFrame => frames.length < AnimationCodec.maxFrames;

  AnimationEditorState copyWith({
    AssetModel? asset,
    List<AnimationFrameModel>? frames,
    int? selectedFrameIndex,
    int? gridRevision,
    Color? currentColor,
    DrawingTool? currentTool,
    String? name,
    List<String>? tags,
    bool? isPlaying,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return AnimationEditorState(
      asset: asset ?? this.asset,
      frames: frames ?? this.frames,
      selectedFrameIndex: selectedFrameIndex ?? this.selectedFrameIndex,
      gridRevision: gridRevision ?? this.gridRevision,
      currentColor: currentColor ?? this.currentColor,
      currentTool: currentTool ?? this.currentTool,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AnimationEditorCubit extends Cubit<AnimationEditorState> {
  final FirebaseRepository firebaseRepository;
  final String userId;
  final bool isNewAsset;

  AnimationEditorCubit(
    this.firebaseRepository,
    this.userId, {
    AssetModel? asset,
    List<AnimationFrameModel>? initialFrames,
  }) : isNewAsset = asset == null,
       super(
         AnimationEditorState(
           asset: asset,
           frames: _initialFrames(asset, initialFrames),
           name: asset?.name ?? '',
           tags: asset?.tags ?? const [],
         ),
       );

  /// A new animation opens on two blank frames, the documented minimum, so the
  /// timeline controls make sense before anything is drawn.
  ///
  /// [initialFrames] seeds a *new* asset from an import and is transient: it
  /// is deep-copied in, never stored, and an existing asset always wins, so
  /// re-entering the editor on a saved animation can never show import
  /// leftovers.
  ///
  /// An existing asset typed ANIMATION but holding a single image - the shape
  /// left by the old stub editor - is padded the same way rather than refused.
  static List<AnimationFrameModel> _initialFrames(
    AssetModel? asset,
    List<AnimationFrameModel>? initialFrames,
  ) {
    final existing = asset?.frames;
    if (existing != null && existing.length >= AnimationCodec.minFrames) {
      return existing.map((frame) => frame.deepCopy()).toList();
    }

    if (asset == null &&
        initialFrames != null &&
        initialFrames.length >= AnimationCodec.minFrames) {
      return initialFrames.map((frame) => frame.deepCopy()).toList();
    }

    final seed = asset?.pixelData;
    if (seed != null) {
      return [
        AnimationFrameModel(
          pixels: seed,
          durationMs: AnimationFrameModel.defaultDurationMs,
        ),
        AnimationFrameModel(
          pixels: seed,
          durationMs: AnimationFrameModel.defaultDurationMs,
        ),
      ];
    }

    return [AnimationFrameModel.blank(), AnimationFrameModel.blank()];
  }

  List<AnimationFrameModel> _copyFrames() =>
      state.frames.map((frame) => frame.deepCopy()).toList();

  /// Replaces the selected frame's grid. Does not bump `gridRevision`: this
  /// comes *from* the pixel editor, which already holds the new grid.
  void updatePixelData(List<List<int>> data) {
    final frames = _copyFrames();
    frames[state.selectedFrameIndex] = frames[state.selectedFrameIndex]
        .copyWith(pixels: data);
    emit(state.copyWith(frames: frames, clearError: true));
  }

  void selectFrame(int index) {
    if (index < 0 || index >= state.frames.length) return;
    if (index == state.selectedFrameIndex) return;
    emit(
      state.copyWith(
        selectedFrameIndex: index,
        gridRevision: state.gridRevision + 1,
      ),
    );
  }

  void addFrame() {
    if (!state.canAddFrame) return;
    final frames = _copyFrames();
    final insertAt = state.selectedFrameIndex + 1;
    frames.insert(insertAt, AnimationFrameModel.blank());
    emit(
      state.copyWith(
        frames: frames,
        selectedFrameIndex: insertAt,
        gridRevision: state.gridRevision + 1,
        clearError: true,
      ),
    );
  }

  void duplicateFrame(int index) {
    if (!state.canAddFrame) return;
    if (index < 0 || index >= state.frames.length) return;
    final frames = _copyFrames();
    // deepCopy, not the same instance: sharing the grid let an edit to the
    // copy write through to the frame it was made from.
    frames.insert(index + 1, frames[index].deepCopy());
    emit(
      state.copyWith(
        frames: frames,
        selectedFrameIndex: index + 1,
        gridRevision: state.gridRevision + 1,
        clearError: true,
      ),
    );
  }

  void deleteFrame(int index) {
    if (!state.canDeleteFrame) return;
    if (index < 0 || index >= state.frames.length) return;
    final frames = _copyFrames();
    frames.removeAt(index);
    final selected = state.selectedFrameIndex >= frames.length
        ? frames.length - 1
        : (state.selectedFrameIndex > index
              ? state.selectedFrameIndex - 1
              : state.selectedFrameIndex);
    emit(
      state.copyWith(
        frames: frames,
        selectedFrameIndex: selected,
        gridRevision: state.gridRevision + 1,
        clearError: true,
      ),
    );
  }

  void reorderFrames(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.frames.length) return;
    final frames = _copyFrames();
    // ReorderableListView reports the insertion point in the pre-removal list.
    var target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target < 0) target = 0;
    if (target >= frames.length) target = frames.length - 1;
    if (target == oldIndex) return;

    final moved = frames.removeAt(oldIndex);
    frames.insert(target, moved);

    // Keep the same frame selected through the move, so the pixel editor does
    // not jump to whatever slid into the old slot.
    var selected = state.selectedFrameIndex;
    if (selected == oldIndex) {
      selected = target;
    } else if (selected > oldIndex && selected <= target) {
      selected -= 1;
    } else if (selected < oldIndex && selected >= target) {
      selected += 1;
    }

    emit(
      state.copyWith(
        frames: frames,
        selectedFrameIndex: selected,
        gridRevision: state.gridRevision + 1,
        clearError: true,
      ),
    );
  }

  void setFrameDuration(int durationMs) {
    final frames = _copyFrames();
    frames[state.selectedFrameIndex] = frames[state.selectedFrameIndex]
        .copyWith(durationMs: durationMs);
    emit(state.copyWith(frames: frames, clearError: true));
  }

  String? get durationError {
    final duration = state.selectedFrame.durationMs;
    if (duration < AnimationCodec.minDurationMs ||
        duration > AnimationCodec.maxDurationMs) {
      return 'Frame duration must be between ${AnimationCodec.minDurationMs}ms '
          'and ${AnimationCodec.maxDurationMs}ms.';
    }
    return null;
  }

  void setCurrentColor(Color color) =>
      emit(state.copyWith(currentColor: color));

  void setCurrentTool(DrawingTool tool) =>
      emit(state.copyWith(currentTool: tool));

  void updateName(String name) =>
      emit(state.copyWith(name: name, clearError: true));

  void addTag(String tag) {
    if (tag.isEmpty || state.tags.contains(tag)) return;
    emit(state.copyWith(tags: [...state.tags, tag]));
  }

  void removeTag(String tag) {
    emit(state.copyWith(tags: state.tags.where((t) => t != tag).toList()));
  }

  void clearGrid() {
    final frames = _copyFrames();
    frames[state.selectedFrameIndex] = frames[state.selectedFrameIndex]
        .copyWith(pixels: AnimationFrameModel.emptyGrid());
    emit(
      state.copyWith(
        frames: frames,
        gridRevision: state.gridRevision + 1,
        clearError: true,
      ),
    );
  }

  void mirrorX() {
    _replaceSelectedGrid(
      state.selectedFrame.pixels.map((row) => row.reversed.toList()).toList(),
    );
  }

  void mirrorY() {
    _replaceSelectedGrid(state.selectedFrame.pixels.reversed.toList());
  }

  void _replaceSelectedGrid(List<List<int>> grid) {
    final frames = _copyFrames();
    frames[state.selectedFrameIndex] = frames[state.selectedFrameIndex]
        .copyWith(pixels: grid);
    emit(
      state.copyWith(
        frames: frames,
        gridRevision: state.gridRevision + 1,
        clearError: true,
      ),
    );
  }

  void setPlaying(bool playing) => emit(state.copyWith(isPlaying: playing));

  void togglePlayback() => emit(state.copyWith(isPlaying: !state.isPlaying));

  /// Restarts the preview from frame 0. Selecting a frame stays possible while
  /// the preview is paused, so editing never has to wait for playback.
  void restartPlayback() {
    emit(state.copyWith(isPlaying: false));
    emit(state.copyWith(isPlaying: true));
  }

  Future<void> save() async {
    if (state.name.trim().isEmpty) {
      emit(state.copyWith(error: 'Name is required'));
      return;
    }

    // Validate before touching the network, so a payload error reads as an
    // editor message instead of a Firestore failure.
    try {
      AnimationCodec.encode(state.frames);
    } on AnimationCodecException catch (e) {
      emit(state.copyWith(error: e.message));
      return;
    }

    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final assetId =
          state.asset?.id ?? 'asset_${DateTime.now().millisecondsSinceEpoch}';

      final asset = AssetModel(
        id: assetId,
        revision: state.asset?.revision ?? 0,
        name: state.name,
        type: AssetType.animation,
        tags: state.tags,
        pixelData: state.frames.first.pixels,
        frames: state.frames,
      );

      if (isNewAsset) {
        await firebaseRepository.createAsset(userId, asset);
      } else {
        await firebaseRepository.updateAsset(assetId, asset);
      }

      emit(
        state.copyWith(
          isLoading: false,
          asset: asset.copyWith(revision: asset.revision + 1),
          clearError: true,
        ),
      );
    } catch (e) {
      // Frames stay in state, so a retry after a transient failure does not
      // start from a blank timeline.
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
