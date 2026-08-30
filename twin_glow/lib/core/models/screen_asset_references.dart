/// The asset references stored on an IMAGE or ANIMATION screen document.
///
/// [assetId] is the legacy fallback kept in sync with [defaultAssetId], while
/// [availableAssetIds] is the pool the physical action button cycles through.
class ScreenAssetReferences {
  final String? assetId;
  final String? defaultAssetId;
  final List<String> availableAssetIds;

  const ScreenAssetReferences({
    this.assetId,
    this.defaultAssetId,
    this.availableAssetIds = const [],
  });

  bool contains(String candidateAssetId) {
    return assetId == candidateAssetId ||
        defaultAssetId == candidateAssetId ||
        availableAssetIds.contains(candidateAssetId);
  }

  /// Removes [removedAssetId] and chooses a valid replacement selection.
  ///
  /// Prefer the existing default or legacy selection when it is not the asset
  /// being removed. Otherwise promote the first remaining pool entry. Both
  /// selected fields are cleared when no asset remains.
  ScreenAssetReferences without(String removedAssetId) {
    final remainingAssetIds = availableAssetIds
        .where((id) => id != removedAssetId)
        .toList(growable: false);

    String? replacementAssetId;
    if (defaultAssetId != null && defaultAssetId != removedAssetId) {
      replacementAssetId = defaultAssetId;
    } else if (assetId != null && assetId != removedAssetId) {
      replacementAssetId = assetId;
    } else if (remainingAssetIds.isNotEmpty) {
      replacementAssetId = remainingAssetIds.first;
    }

    return ScreenAssetReferences(
      assetId: replacementAssetId,
      defaultAssetId: replacementAssetId,
      availableAssetIds: remainingAssetIds,
    );
  }
}
