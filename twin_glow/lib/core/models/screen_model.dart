enum ScreenType { clock, image, animation, sensor, game }

class ScreenModel {
  final String id;
  final ScreenType type;
  final String? name;
  final bool enabled;
  final bool isShared;
  final List<List<int>>? previewData; // 16x16 pixel grid
  final String? assetId; // Legacy single-image field, kept as fallback
  final Map<String, dynamic>? config; // Screen-specific config

  // Asset pool. IMAGE/ANIMATION only - the device cycles through these with
  // the action button. Empty means "fall back to the single assetId".
  final String? defaultAssetId;
  final List<String> availableAssetIds;
  final bool allowManualSwitch;
  final String? sharedScreenId;
  final int? sharedVersion;

  ScreenModel({
    required this.id,
    required this.type,
    this.name,
    this.enabled = true,
    this.isShared = false,
    this.previewData,
    this.assetId,
    this.config,
    this.defaultAssetId,
    this.availableAssetIds = const [],
    this.allowManualSwitch = true,
    this.sharedScreenId,
    this.sharedVersion,
  });

  /// Whether this screen type can carry an asset pool.
  bool get supportsAssetPool =>
      type == ScreenType.image || type == ScreenType.animation;

  ScreenModel copyWith({
    String? id,
    ScreenType? type,
    String? name,
    bool? enabled,
    bool? isShared,
    List<List<int>>? previewData,
    String? assetId,
    Map<String, dynamic>? config,
    String? defaultAssetId,
    List<String>? availableAssetIds,
    bool? allowManualSwitch,
    String? sharedScreenId,
    int? sharedVersion,
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
      defaultAssetId: defaultAssetId ?? this.defaultAssetId,
      availableAssetIds: availableAssetIds ?? this.availableAssetIds,
      allowManualSwitch: allowManualSwitch ?? this.allowManualSwitch,
      sharedScreenId: sharedScreenId ?? this.sharedScreenId,
      sharedVersion: sharedVersion ?? this.sharedVersion,
    );
  }

  String get displayName => name ?? type.name.toUpperCase();
}
