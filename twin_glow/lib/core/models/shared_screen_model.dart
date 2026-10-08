import 'asset_model.dart';
import 'screen_model.dart';

/// A partner-visible copy of a screen's default content, not a local playlist
/// entry or permission to edit the partner's private Firestore documents.
class SharedScreenModel {
  final String id, deviceId, name;
  final AssetModel asset;

  const SharedScreenModel({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.asset,
  });

  ScreenModel get previewScreen => ScreenModel(
    id: id,
    type: asset.type == AssetType.animation
        ? ScreenType.animation
        : ScreenType.image,
    name: name,
    isShared: true,
    assetId: asset.id,
  );
}
