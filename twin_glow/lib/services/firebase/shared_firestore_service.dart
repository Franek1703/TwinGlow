import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/pairing_model.dart';
import '../../core/models/screen_model.dart';

/// Shared content remains in /assets. Device documents contain local references.
class SharedFirestoreService {
  final FirebaseFirestore db;
  final String uid;
  SharedFirestoreService(this.db, this.uid);
  DocumentReference<Map<String, dynamic>> grant(String id) =>
      db.doc('sharingPairs/$id');
  DocumentReference<Map<String, dynamic>> shared(String id) =>
      db.doc('sharedScreens/$id');
  DocumentReference<Map<String, dynamic>> screen(String device, String id) =>
      db.doc('devices/$device/screens/$id');

  Future<void> initializeOrder(String device, {String? pairId}) async {
    final ref = db.doc('playlistState/$device');
    final existing = await ref.get(const GetOptions(source: Source.server));
    if (existing.exists) {
      if (pairId != null && existing.data()?['pairId'] != pairId) {
        await ref.update({'pairId': pairId});
      }
      return;
    }
    final deviceRef = db.doc('devices/$device');
    final before = await deviceRef.get(const GetOptions(source: Source.server));
    final last = await db
        .collection('devices/$device/screens')
        .orderBy('order', descending: true)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    final next = last.docs.isEmpty
        ? 0
        : (last.docs.first.data()['order'] as num).toInt() + 1;
    await db.runTransaction((tx) async {
      final current = await tx.get(deviceRef);
      final counter = await tx.get(ref);
      if (counter.exists) return;
      if (current.data()?['configVersion'] != before.data()?['configVersion']) {
        throw StateError('Playlist changed. Refresh and try again.');
      }
      tx.set(ref, {'nextOrder': next, 'pairId': pairId ?? ''});
    });
  }

  /// Each app signs its own consent only after verifying the active RTDB pair.
  Future<bool> consent(PairingModel pair) async {
    if (!pair.isPaired ||
        pair.pairId == null ||
        pair.deviceId == null ||
        pair.partnerDeviceId == null) {
      return false;
    }
    await initializeOrder(pair.deviceId!, pairId: pair.pairId);
    final a = uid.compareTo(pair.pairedUserId!) < 0;
    final identity = {
      'userA': a ? uid : pair.pairedUserId!,
      'userB': a ? pair.pairedUserId! : uid,
      'deviceA': a ? pair.deviceId! : pair.partnerDeviceId!,
      'deviceB': a ? pair.partnerDeviceId! : pair.deviceId!,
    };
    return db.runTransaction((tx) async {
      final ref = grant(pair.pairId!);
      final snapshot = await tx.get(ref);
      final data = snapshot.data();
      if (data == null) {
        tx.set(ref, {
          ...identity,
          'schemaVersion': 1,
          'acceptedA': a,
          'acceptedB': !a,
          'state': 'PENDING',
          'contentVersion': 0,
        });
        return false;
      }
      for (final key in identity.keys) {
        if (data[key] != identity[key]) {
          throw StateError('Sharing identity mismatch');
        }
      }
      if (data['state'] == 'CLOSING') return false;
      if (data['state'] == 'REVOKED') {
        throw StateError(
          'Sharing consent has been revoked. Pair the devices again.',
        );
      }
      final own = a ? 'acceptedA' : 'acceptedB';
      final other = a ? 'acceptedB' : 'acceptedA';
      if (data[own] != true) {
        tx.update(ref, {
          own: true,
          'state': data[other] == true ? 'ACTIVE' : 'PENDING',
        });
      }
      return data[other] == true;
    });
  }

  static List<String> pool(Map<String, dynamic> data) {
    final result = <String>{
      ...List<String>.from(data['availableAssetIds'] ?? const []),
    };
    for (final key in ['defaultAssetId', 'assetId']) {
      if (data[key] is String && (data[key] as String).isNotEmpty) {
        result.add(data[key]);
      }
    }
    return result.toList();
  }

  static Map<String, dynamic> content(ScreenModel model) => {
    'name': model.displayName,
    'type': model.type.name.toUpperCase(),
    'availableAssetIds':
        model.availableAssetIds.isEmpty && model.assetId != null
        ? [model.assetId!]
        : model.availableAssetIds,
    'defaultAssetId': model.defaultAssetId ?? model.assetId,
    'allowManualSwitch': model.allowManualSwitch,
    'config': model.config ?? <String, dynamic>{},
  };

  static String sourceFingerprint(Map<String, dynamic> d) => jsonEncode({
    for (final k in [
      'type',
      'name',
      'order',
      'enabled',
      'durationMs',
      'assetId',
      'defaultAssetId',
      'availableAssetIds',
      'allowManualSwitch',
      'config',
      'sharedScreenId',
    ])
      k: d[k],
  });

  static bool sameContent(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(a) == jsonEncode(b);

  static void validate(Map<String, dynamic> data) {
    final ids = pool(data);
    if (!['IMAGE', 'ANIMATION'].contains(data['type']) ||
        ids.isEmpty ||
        ids.length > 10 ||
        !ids.contains(data['defaultAssetId'])) {
      throw StateError(
        'Choose 1–10 matching assets and a default before sharing.',
      );
    }
  }

  /// Stage is invisible to devices. Only final transaction exposes references.
  Future<String> publish(
    PairingModel pair,
    String device,
    String localId,
    ScreenModel model,
  ) async {
    if (pair.deviceId != device || !await consent(pair)) {
      throw StateError(
        'Open the updated app on both accounts to enable shared screens.',
      );
    }
    final source = (await screen(
      device,
      localId,
    ).get(const GetOptions(source: Source.server))).data()!;
    final base = 'ss_${pair.pairId}_${device}_$localId';
    var id = base;
    var staged = await shared(id).get(const GetOptions(source: Source.server));
    var generation = 0;
    while (staged.data()?['state'] == 'REVOKED') {
      id = '${base}_${++generation}';
      staged = await shared(id).get(const GetOptions(source: Source.server));
    }
    if (staged.data()?['state'] == 'ACTIVE') return id;
    final ref = shared(id);
    final peer = pair.partnerDeviceId!;
    final peerRefId = 'shared_$id';
    // Content and concurrency guard come from the same authoritative snapshot.
    final data = {
      'name': source['name'] ?? 'Shared screen',
      'type': (source['type'] as String).toUpperCase(),
      'availableAssetIds': pool(source),
      'defaultAssetId': source['defaultAssetId'] ?? source['assetId'],
      'allowManualSwitch': source['allowManualSwitch'] ?? true,
      'config': source['config'] ?? <String, dynamic>{},
    };
    validate(data);
    if (!staged.exists) {
      await ref.set({
        ...data,
        'schemaVersion': 2,
        'pairId': pair.pairId,
        'createdBy': uid,
        'state': 'STAGING',
        'contentVersion': 0,
        'screenRefs': {device: localId, peer: peerRefId},
      });
    }
    await _writeContent(
      id,
      data,
      expectedVersion: staged.data()?['state'] == 'ACTIVE'
          ? model.sharedVersion
          : null,
      attach: true,
      expectedSource: sourceFingerprint(source),
    );
    return id;
  }

  Future<void> update(
    String id,
    ScreenModel model, {
    String? localDevice,
    String? localScreen,
  }) => _writeContent(
    id,
    content(model),
    expectedVersion: model.sharedVersion,
    localDevice: localDevice,
    localScreen: localScreen,
    localEnabled: model.enabled,
  );

  Future<void> _writeContent(
    String id,
    Map<String, dynamic> input, {
    int? expectedVersion,
    bool attach = false,
    String? expectedSource,
    String? localDevice,
    String? localScreen,
    bool localEnabled = true,
  }) async {
    validate(input);
    // Public templates stay immutable; editable copies still live in /assets.
    final data = Map<String, dynamic>.from(input);
    final copied = <String, String>{};
    for (final assetId in pool(data)) {
      final asset = await db
          .doc('assets/$assetId')
          .get(const GetOptions(source: Source.server));
      if (!asset.exists) throw StateError('Asset $assetId no longer exists');
      if (asset.data()?['isDefault'] == true) {
        final copyId = SharedFirestoreService.copyId('copy', id, assetId);
        final copy = db.doc('assets/$copyId');
        await db.runTransaction((tx) async {
          final existing = await tx.get(copy);
          if (!existing.exists) {
            tx.set(copy, {
              ...asset.data()!,
              'ownerUid': uid,
              'isDefault': false,
            });
          }
        });
        copied[assetId] = copyId;
      }
    }
    data['availableAssetIds'] = pool(
      data,
    ).map((id) => copied[id] ?? id).toList();
    data['defaultAssetId'] =
        copied[data['defaultAssetId']] ?? data['defaultAssetId'];
    var operation = 'reading the shared screen';
    final publication = db.runTransaction((tx) async {
      operation = 'reading the shared screen';
      final ref = shared(id);
      final snapshot = await tx.get(ref);
      final old = snapshot.data()!;
      final pairId = old['pairId'] as String;
      operation = 'reading partner consent';
      final access = await tx.get(grant(pairId));
      final g = access.data()!;
      if (g['state'] != 'ACTIVE' || old['state'] == 'REVOKED') {
        throw StateError('Sharing is no longer active');
      }
      if (expectedVersion != null && old['contentVersion'] != expectedVersion) {
        throw StateError(
          'Shared screen changed elsewhere. Refresh before saving.',
        );
      }
      final refs = Map<String, dynamic>.from(old['screenRefs'] as Map);
      final initial = old['state'] == 'STAGING';
      final device = g[g['userA'] == uid ? 'deviceA' : 'deviceB'] as String;
      final peer = g[g['userA'] == uid ? 'deviceB' : 'deviceA'] as String;
      operation = 'reading the source screen';
      final local = initial
          ? await tx.get(screen(device, refs[device] as String))
          : null;
      operation = 'reading the partner playlist position';
      final counter = initial
          ? await tx.get(db.doc('playlistState/$peer'))
          : null;
      final all = {...pool(old), ...pool(data)};
      final assets = <String, Map<String, dynamic>>{};
      for (final assetId in all) {
        operation = 'reading animation or image asset $assetId';
        final a = await tx.get(db.doc('assets/$assetId'));
        if (!a.exists) throw StateError('Asset $assetId no longer exists');
        assets[assetId] = a.data()!;
      }
      if (initial &&
          (local?.data()?['sharedScreenId'] != null || !counter!.exists)) {
        throw StateError('Playlist changed during sharing');
      }
      if (initial &&
          expectedSource != null &&
          sourceFingerprint(local!.data()!) != expectedSource) {
        throw StateError('Source screen changed during sharing. Refresh.');
      }
      if (initial && !attach) throw StateError('Shared screen is not ready');
      for (final assetId in pool(data)) {
        final asset = assets[assetId]!;
        if ((asset['type'] as String? ?? 'IMAGE').toUpperCase() !=
            data['type']) {
          throw StateError(
            'Image and animation screens require matching assets',
          );
        }
        if (asset['sharingPairId'] != null &&
            asset['sharingPairId'] != pairId &&
            (asset['sharedScreenIds'] as List? ?? []).isNotEmpty) {
          throw StateError('Asset is shared through another pair');
        }
      }
      operation = 'committing the shared screen and playlist references';
      for (final assetId in all) {
        final asset = assets[assetId]!;
        if (asset['isDefault'] == true) continue;
        final links = List<String>.from(asset['sharedScreenIds'] ?? const []);
        if (pool(data).contains(assetId)) {
          if (!links.contains(id)) links.add(id);
        } else {
          links.remove(id);
        }
        if (links.length > 32) {
          throw StateError('An asset can belong to at most 32 shared screens');
        }
        tx.update(db.doc('assets/$assetId'), {
          'sharedScreenIds': links,
          'sharingPairId': links.isEmpty ? FieldValue.delete() : pairId,
          'sharingMutationScreenId': id,
        });
      }
      tx.update(ref, {
        ...data,
        'state': 'ACTIVE',
        'contentVersion': (old['contentVersion'] as int) + 1,
      });
      tx.update(grant(pairId), {
        'contentVersion': (g['contentVersion'] as int) + 1,
        'mutationKind': 'SCREEN',
        'mutationId': id,
      });
      if (!initial && localDevice != null && localScreen != null) {
        tx.update(screen(localDevice, localScreen), {'enabled': localEnabled});
        tx.update(db.doc('devices/$localDevice'), {
          'configVersion': FieldValue.increment(1),
        });
      }
      if (initial) {
        final localData = local!.data()!;
        // Preserve identity and local settings, strip all shared content.
        // A masked update preserves the read version precondition and avoids
        // the full-overwrite permission failure on an existing private screen.
        tx.update(screen(device, refs[device] as String), {
          'sharedScreenId': id,
          'order': localData['order'] ?? 0,
          'enabled': localData['enabled'] ?? true,
          'durationMs': localData['durationMs'] ?? 10000,
          for (final key in localData.keys)
            if (!{
              'sharedScreenId',
              'order',
              'enabled',
              'durationMs',
            }.contains(key))
              key: FieldValue.delete(),
        });
        tx.set(screen(peer, refs[peer] as String), {
          'sharedScreenId': id,
          'order': counter!.data()!['nextOrder'],
          'enabled': true,
          'durationMs': 10000,
        });
        tx.update(db.doc('playlistState/$peer'), {
          'nextOrder': (counter.data()!['nextOrder'] as int) + 1,
          'lastSharedScreenId': id,
        });
        tx.update(db.doc('devices/$device'), {
          'configVersion': FieldValue.increment(1),
        });
      }
    });
    await publication.onError<FirebaseException>((error, stackTrace) {
      Error.throwWithStackTrace(
        FirebaseException(
          plugin: error.plugin,
          code: error.code,
          message:
              'Sharing failed while $operation. ${error.message ?? error.code}',
        ),
        stackTrace,
      );
    });
  }

  static String copyId(String kind, String screenId, String assetId) =>
      '${kind}_${sha256.convert(utf8.encode(jsonEncode([screenId, assetId])))}';

  Future<void> beginClosing(PairingModel pair) async {
    await db.runTransaction((tx) async {
      final ref = grant(pair.pairId!);
      final data = (await tx.get(ref)).data();
      if (data == null) {
        final a = uid.compareTo(pair.pairedUserId!) < 0;
        tx.set(ref, {
          'schemaVersion': 1,
          'userA': a ? uid : pair.pairedUserId!,
          'userB': a ? pair.pairedUserId! : uid,
          'deviceA': a ? pair.deviceId! : pair.partnerDeviceId!,
          'deviceB': a ? pair.partnerDeviceId! : pair.deviceId!,
          'acceptedA': a,
          'acceptedB': !a,
          'state': 'CLOSING',
          'contentVersion': 0,
        });
      } else if (!['CLOSING', 'REVOKED'].contains(data['state'])) {
        tx.update(ref, {'state': 'CLOSING'});
      }
    });
  }

  Future<void> stop(String id) async {
    await db.runTransaction((tx) async {
      final ref = shared(id);
      final s = (await tx.get(ref)).data()!;
      if (s['state'] == 'REVOKED') return;
      final access = grant(s['pairId'] as String);
      final g = (await tx.get(access)).data()!;
      if (!['ACTIVE', 'CLOSING'].contains(g['state'])) {
        throw StateError('Sharing cleanup is unavailable');
      }
      if (s['state'] == 'STAGING') {
        // No references or permissions were published for this stage.
        tx.update(ref, {
          'state': 'REVOKED',
          'contentVersion': (s['contentVersion'] as int) + 1,
        });
        tx.update(access, {
          'contentVersion': (g['contentVersion'] as int) + 1,
          'mutationKind': 'SCREEN',
          'mutationId': id,
        });
        return;
      }
      final refs = Map<String, dynamic>.from(s['screenRefs'] as Map);
      final assets = <String, Map<String, dynamic>>{};
      for (final assetId in pool(s)) {
        assets[assetId] = (await tx.get(db.doc('assets/$assetId'))).data()!;
      }
      final retained = <String, String>{};
      for (final entry in assets.entries) {
        if (entry.value['ownerUid'] != s['createdBy']) {
          final copyId = SharedFirestoreService.copyId(
            'retained',
            id,
            entry.key,
          );
          retained[entry.key] = copyId;
          final copy = Map<String, dynamic>.from(entry.value)
            ..remove('sharingPairId')
            ..remove('sharedScreenIds')
            ..remove('sharingMutationScreenId');
          tx.set(db.doc('assets/$copyId'), {
            ...copy,
            'ownerUid': s['createdBy'],
            'retainedFrom': entry.key,
            'retainedScreenId': id,
          });
        }
        final links = List<String>.from(
          entry.value['sharedScreenIds'] ?? const [],
        )..remove(id);
        tx.update(db.doc('assets/${entry.key}'), {
          'sharedScreenIds': links,
          'sharingPairId': links.isEmpty ? FieldValue.delete() : s['pairId'],
          'sharingMutationScreenId': id,
        });
      }
      final ids = pool(s).map((a) => retained[a] ?? a).toList();
      final defaultId = retained[s['defaultAssetId']] ?? s['defaultAssetId'];
      for (final entry in refs.entries) {
        final r = screen(entry.key, entry.value as String);
        final creatorDevice =
            g[s['createdBy'] == g['userA'] ? 'deviceA' : 'deviceB'];
        if (entry.key == creatorDevice) {
          tx.update(r, {
            'sharedScreenId': FieldValue.delete(),
            'name': s['name'],
            'type': (s['type'] as String).toLowerCase(),
            'isShared': false,
            'availableAssetIds': ids,
            'defaultAssetId': defaultId,
            'assetId': defaultId,
            'allowManualSwitch': s['allowManualSwitch'],
            'config': s['config'],
          });
        } else {
          tx.delete(r);
        }
      }
      tx.update(ref, {
        'state': 'REVOKED',
        'availableAssetIds': ids,
        'defaultAssetId': defaultId,
        'contentVersion': (s['contentVersion'] as int) + 1,
      });
      tx.update(access, {
        'contentVersion': (g['contentVersion'] as int) + 1,
        'mutationKind': 'SCREEN',
        'mutationId': id,
      });
    });
  }

  Future<void> revoke(String pairId) async {
    final ref = grant(pairId);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (snapshot.exists && snapshot.data()?['state'] != 'REVOKED') {
        tx.update(ref, {'state': 'REVOKED'});
      }
    });
  }
}
