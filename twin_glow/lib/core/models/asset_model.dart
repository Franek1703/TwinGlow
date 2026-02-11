enum AssetType {
  image,
  animation,
}

class AssetModel {
  final String id;
  final String name;
  final AssetType type;
  final List<String> tags;
  final List<List<int>>? pixelData; // 16x16 for images, frames for animations
  final bool isDefault;
  final DateTime? createdAt;

  AssetModel({
    required this.id,
    required this.name,
    required this.type,
    this.tags = const [],
    this.pixelData,
    this.isDefault = false,
    this.createdAt,
  });

  AssetModel copyWith({
    String? id,
    String? name,
    AssetType? type,
    List<String>? tags,
    List<List<int>>? pixelData,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return AssetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      pixelData: pixelData ?? this.pixelData,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
