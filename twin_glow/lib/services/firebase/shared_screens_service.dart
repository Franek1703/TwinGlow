import 'dart:convert';
import '../../core/codecs/animation_codec.dart';
import '../../core/models/asset_model.dart';
import '../../core/models/pairing_model.dart';
import '../../core/models/screen_model.dart';
import '../../core/models/shared_screen_model.dart';
import 'asset_document.dart';
import 'pairing_service.dart';

/// The catalog is separate from device mailboxes: publishing an app preview
/// must not claim that an ESP32 sent or displayed an event.
class SharedScreensService {
  final PairingStore store;
  final String uid;
  SharedScreensService(this.store, this.uid);

  Future<void> sync(
    PairingModel pair,
    List<ScreenModel> screens,
    List<AssetModel> assets, {
    required int sourceVersion,
  }) async {
    if (!pair.isPaired || pair.pairId == null || pair.deviceId == null) return;
    final next = <String, Map<String, dynamic>>{};
    for (final screen in screens) {
      if (!screen.isShared || !screen.supportsAssetPool) continue;
      final id =
          screen.defaultAssetId ??
          screen.assetId ??
          (screen.availableAssetIds.isEmpty
              ? null
              : screen.availableAssetIds.first);
      final matches = assets.where((a) => a.id == id);
      // A deleted/unselected asset removes its preview; failed fetches throw
      // before sync, leaving the working catalog intact.
      if (matches.isEmpty) continue;
      final asset = matches.first;
      if ((screen.type == ScreenType.animation) !=
          (asset.type == AssetType.animation)) {
        continue;
      }
      next[screen.id] = {
        'schemaVersion': 1,
        'deviceId': pair.deviceId,
        'screenId': screen.id,
        'name': screen.displayName,
        'assetId': asset.id,
        'assetName': asset.name,
        'content': {
          'type': asset.type.name.toUpperCase(),
          ...buildAssetPixelFields(asset).values,
        },
      };
    }
    final path = 'pairing/sharedScreens/${pair.pairId}/$uid';
    final previous = pairingMap(await store.read(path));
    final previousScreens = pairingMap(previous['screens']);
    final previousVersion = previous['sourceVersion'] as int?;
    if (previousVersion != null && sourceVersion <= previousVersion) {
      if (sourceVersion == previousVersion && _same(previousScreens, next)) {
        return;
      }
      throw StateError(
        'Shared content changed elsewhere. Refresh and try again.',
      );
    }
    // Keep the revision even when there are no screens: a delayed older
    // publisher must not resurrect a preview after sharing was disabled.
    await store.update({
      path: {
        'sourceVersion': sourceVersion,
        'updatedAt': pairingTimestamp,
        'screens': next,
      },
    });
  }

  Stream<List<SharedScreenModel>> watch(String pairId, String ownerUid) => store
      .watch('pairing/sharedScreens/$pairId/$ownerUid')
      .map((value) => decodeSharedScreens(pairingMap(value)['screens']));
}

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}

List<SharedScreenModel> decodeSharedScreens(Object? value) {
  final result = <SharedScreenModel>[];
  for (final entry in pairingMap(value).entries) {
    try {
      final data = pairingMap(entry.value);
      final content = pairingMap(data['content']);
      if (data['schemaVersion'] != 1 ||
          data['screenId'] != entry.key ||
          jsonEncode(content).length > 12288) {
        continue;
      }
      final animation = content['type'] == 'ANIMATION';
      if (!animation && content['type'] != 'IMAGE') continue;
      List<AnimationFrameModel>? frames;
      List<List<int>>? pixels;
      if (animation) {
        if (content['encoding'] != AnimationCodec.encodingName) continue;
        frames = AnimationCodec.decode(
          basePixelsPacked: content['basePixelsPacked'] as String,
          frameDeltasPacked: List<String>.from(
            content['frameDeltasPacked'] as List,
          ),
          frameDurationsMs: List<int>.from(content['frameDurationsMs'] as List),
        );
        if (frames.length < 2 || frames.length != content['frameCount']) {
          continue;
        }
        if (content['loop'] != true) continue;
        AnimationCodec.encode(frames);
      } else {
        if (content['encoding'] != 'SPARSE_PACKED_V1') continue;
        final packed = content['pixelsPacked'] as String;
        if (packed.length > 2048 ||
            packed.length % 8 != 0 ||
            !RegExp(r'^[0-9a-fA-F]*$').hasMatch(packed)) {
          continue;
        }
        pixels = AnimationFrameModel.emptyGrid();
        for (var i = 0; i < packed.length; i += 8) {
          final index = int.parse(packed.substring(i, i + 2), radix: 16);
          final color = int.parse(packed.substring(i + 2, i + 8), radix: 16);
          pixels[index ~/ 16][index % 16] = 0xff000000 | color;
        }
      }
      result.add(
        SharedScreenModel(
          id: entry.key,
          deviceId: data['deviceId'] as String,
          name: data['name'] as String,
          asset: AssetModel(
            id: data['assetId'] as String,
            name: data['assetName'] as String,
            type: animation ? AssetType.animation : AssetType.image,
            frames: frames,
            pixelData: pixels,
          ),
        ),
      );
    } catch (_) {
      // One malformed historical entry must not hide the rest of the catalog.
    }
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return result;
}
