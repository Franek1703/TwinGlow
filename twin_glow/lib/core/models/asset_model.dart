enum AssetType {
  image,
  animation,
}

/// One authored frame of an animation: a full 16x16 grid plus how long it
/// stays on screen.
///
/// Frames are stored as complete grids in the app even though they travel to
/// Firestore as deltas. Authoring against whole frames keeps the editor's
/// undo/duplicate semantics simple, and the codec is the only place that has
/// to reason about transitions.
class AnimationFrameModel {
  final List<List<int>> pixels; // 16x16 ARGB, 0 = off
  final int durationMs;

  AnimationFrameModel({
    required List<List<int>> pixels,
    required this.durationMs,
  }) : pixels = copyGrid(pixels);

  AnimationFrameModel.blank({this.durationMs = defaultDurationMs})
      : pixels = emptyGrid();

  static const int defaultDurationMs = 200;

  AnimationFrameModel copyWith({
    List<List<int>>? pixels,
    int? durationMs,
  }) {
    return AnimationFrameModel(
      pixels: pixels ?? this.pixels,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  /// A frame whose grid shares no references with this one. Duplicating a
  /// frame without this let edits to the copy write through to the original.
  AnimationFrameModel deepCopy() => AnimationFrameModel(
        pixels: pixels,
        durationMs: durationMs,
      );

  bool get hasVisiblePixel =>
      pixels.any((row) => row.any((value) => (value & 0xFFFFFF) != 0));

  static List<List<int>> emptyGrid() =>
      List.generate(16, (_) => List.filled(16, 0));

  static List<List<int>> copyGrid(List<List<int>> source) {
    return List.generate(
      16,
      (y) => List.generate(
        16,
        (x) => y < source.length && x < source[y].length ? source[y][x] : 0,
      ),
    );
  }
}

class AssetModel {
  final String id;
  final String name;
  final AssetType type;
  final List<String> tags;
  final List<List<int>>? pixelData; // 16x16 for images, first frame for animations
  final List<AnimationFrameModel>? frames; // animations only
  final bool isDefault;
  final DateTime? createdAt;

  AssetModel({
    required this.id,
    required this.name,
    required this.type,
    this.tags = const [],
    this.pixelData,
    this.frames,
    this.isDefault = false,
    this.createdAt,
  });

  /// The grid to show in a static thumbnail. Animations preview on their first
  /// frame so a library grid stays cheap; only the editor and the active
  /// screen preview play the whole sequence.
  List<List<int>>? get previewPixelData {
    final frameList = frames;
    if (frameList != null && frameList.isNotEmpty) {
      return frameList.first.pixels;
    }
    return pixelData;
  }

  AssetModel copyWith({
    String? id,
    String? name,
    AssetType? type,
    List<String>? tags,
    List<List<int>>? pixelData,
    List<AnimationFrameModel>? frames,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return AssetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      pixelData: pixelData ?? this.pixelData,
      frames: frames ?? this.frames,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
