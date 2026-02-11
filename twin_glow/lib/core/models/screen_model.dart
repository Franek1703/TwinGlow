enum ScreenType {
  clock,
  image,
  animation,
  sensor,
  game,
}

class ScreenModel {
  final String id;
  final ScreenType type;
  final String? name;
  final bool enabled;
  final bool isShared;
  final List<List<int>>? previewData; // 16x16 pixel grid
  final String? assetId; // For IMAGE/ANIMATION screens
  final Map<String, dynamic>? config; // Screen-specific config

  ScreenModel({
    required this.id,
    required this.type,
    this.name,
    this.enabled = true,
    this.isShared = false,
    this.previewData,
    this.assetId,
    this.config,
  });

  ScreenModel copyWith({
    String? id,
    ScreenType? type,
    String? name,
    bool? enabled,
    bool? isShared,
    List<List<int>>? previewData,
    String? assetId,
    Map<String, dynamic>? config,
  }) {
    return ScreenModel(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      isShared: isShared ?? this.isShared,
      previewData: previewData ?? this.previewData,
      assetId: assetId ?? this.assetId,
      config: config ?? this.config,
    );
  }

  String get displayName => name ?? type.name.toUpperCase();
}
