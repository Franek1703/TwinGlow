import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_repository.dart';
import 'pairing_service.dart';
import 'firebase_pairing_store.dart';
import 'shared_screens_service.dart';
import 'shared_catalog_queue.dart';
import 'device_access.dart';
import '../../core/models/device_model.dart';
import '../../core/models/screen_model.dart';
import '../../core/models/screen_asset_references.dart';
import '../../core/models/asset_model.dart';
import '../../core/codecs/animation_codec.dart';
import 'asset_document.dart';
import '../../core/models/user_model.dart';
import '../../core/models/pairing_model.dart';
import '../../core/models/shared_screen_model.dart';
import '../../core/utils/device_presence.dart';

class FirebaseRepositoryImpl implements FirebaseRepository {
  static final _sharedCatalogQueue = SharedCatalogQueue();
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;
  FirebaseRepositoryImpl({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseDatabase? database,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _database = database ?? FirebaseDatabase.instance;
  PairingService _pairing(String uid) {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Authentication required');
    }
    return PairingService(
      FirebasePairingStore(_database),
      uid,
      user.email ?? '',
    );
  }

  Future<void> _ensurePairingProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _pairing(user.uid).ensureProfile();
    } catch (e) {
      debugPrint('Pairing directory update failed: $e');
    }
  }

  // Auth methods
  @override
  Future<UserModel?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _ensurePairingProfile();
      return _userFromFirebaseUser(credential.user);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  @override
  Future<UserModel?> signUp(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document in Firestore
      if (credential.user != null) {
        await _firestore.collection('users').doc(credential.user!.uid).set({
          'email': email,
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      await _ensurePairingProfile();
      return _userFromFirebaseUser(credential.user);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    await _ensurePairingProfile();
    // Fetch user document for displayName
    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();

    return UserModel(
      id: user.uid,
      email: user.email ?? '',
      displayName: data?['displayName'] ?? user.displayName,
      photoUrl: user.photoURL,
    );
  }

  // Device methods
  @override
  Future<List<DeviceModel>> getDevices(String userId) async {
    try {
      // Query user's device mappings from /users/{uid}/devices
      final mappingSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('devices')
          .get();
      if (mappingSnapshot.docs.isEmpty) return [];

      return loadOwnedDeviceMappings<
        QueryDocumentSnapshot<Map<String, dynamic>>,
        DeviceModel
      >(
        mappings: mappingSnapshot.docs,
        userId: userId,
        deviceId: (mapping) => mapping.id,
        readAccess: (id) async =>
            (await _database.ref('deviceAccess/$id').get()).value,
        load: (mapping) async {
          final id = mapping.id;
          final doc = await _firestore.collection('devices').doc(id).get();
          if (!doc.exists) return null;
          final data = doc.data()!;
          final device = _deviceFromFirestore(id, {
            ...data,
            'name':
                (mapping.data()['nameOverride'] as String?) ??
                data['name'] as String? ??
                '',
            'hasSensor': data['hw'] != null && data['hw']['bme680'] == true,
          });
          final presence = await _database.ref('presence/$id').get();
          return device.copyWith(
            isOnline: isPresenceOnline(
              presence.exists ? presence.value as Map<dynamic, dynamic>? : null,
            ),
          );
        },
      );
    } catch (e) {
      print('error: $e');
      throw Exception('Failed to get devices: $e');
    }
  }

  @override
  Future<DeviceModel> createDevice(String userId, DeviceModel device) async {
    try {
      await _firestore.collection('devices').doc(device.id).set({
        'name': device.name,
        'userId': userId,
        'hasSensor': device.hasSensor,
        'isOnline': false,
        'configVersion': 1,
        'timezone': device.timezone,
        'tzPosix': device.tzPosix,
        'brightness': device.brightness ?? kDefaultBrightness,
        'sleepMode': _sleepModeToMap(device.sleepMode ?? const SleepSchedule()),
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
      return device;
    } catch (e) {
      throw Exception('Failed to create device: $e');
    }
  }

  @override
  Future<void> updateDevice(String deviceId, DeviceModel device) async {
    try {
      final deviceRef = _firestore.collection('devices').doc(deviceId);

      await deviceRef.update({
        'name': device.name,
        'hasSensor': device.hasSensor,
        // Kept inside this one update so the bump lands atomically with the
        // data it describes; increment avoids the lost-update race.
        'configVersion': FieldValue.increment(1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        // Only written when set, so an update that carries no timezone (an
        // older caller, or a model built without one) cannot wipe the zone the
        // device is already running on.
        if (device.timezone != null) 'timezone': device.timezone,
        if (device.tzPosix != null) 'tzPosix': device.tzPosix,
        // Same rule as the timezone above: a model built without these must not
        // wipe the values the device is already running on.
        if (device.brightness != null) 'brightness': device.brightness,
        if (device.sleepMode != null)
          'sleepMode': _sleepModeToMap(device.sleepMode!),
      });

      await _ringConfigDoorbell(deviceId);
    } catch (e) {
      throw Exception('Failed to update device: $e');
    }
  }

  @override
  Future<void> deleteDevice(String deviceId) async {
    try {
      // Delete device document
      await _firestore.collection('devices').doc(deviceId).delete();

      // Delete all screens for this device
      final screensSnapshot = await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens')
          .get();

      final batch = _firestore.batch();
      for (var doc in screensSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete device: $e');
    }
  }

  // Screen methods
  @override
  Future<List<ScreenModel>> getScreens(String deviceId) async {
    try {
      final querySnapshot = await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens')
          .orderBy('order')
          .get();

      return querySnapshot.docs.map((doc) {
        return _screenFromFirestore(doc.id, doc.data());
      }).toList();
    } catch (e) {
      throw Exception('Failed to get screens: $e');
    }
  }

  @override
  Future<ScreenModel> createScreen(String deviceId, ScreenModel screen) async {
    try {
      final screensRef = _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens');

      // Get current max order
      final existingScreens = await screensRef
          .orderBy('order', descending: true)
          .limit(1)
          .get();
      final nextOrder = existingScreens.docs.isEmpty
          ? 0
          : (existingScreens.docs.first.data()['order'] as int? ?? 0) + 1;

      await screensRef.doc(screen.id).set({
        'type': screen.type.name,
        'name': screen.name,
        'enabled': screen.enabled,
        'isShared': screen.isShared,
        'order': nextOrder,
        'assetId': screen.assetId,
        'config': screen.config,
        'previewData': screen.previewData,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        ..._poolFields(screen),
      });

      // Increment device configVersion
      await _incrementDeviceConfigVersion(deviceId);

      await _syncSharedScreensForDevice(deviceId);
      return screen;
    } catch (e) {
      throw Exception('Failed to create screen: $e');
    }
  }

  @override
  Future<void> updateScreen(
    String deviceId,
    String screenId,
    ScreenModel screen,
  ) async {
    try {
      await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens')
          .doc(screenId)
          .update({
            'name': screen.name,
            'enabled': screen.enabled,
            'isShared': screen.isShared,
            'assetId': screen.assetId,
            'config': screen.config,
            'previewData': screen.previewData,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
            ..._poolFields(screen),
          });

      // Increment device configVersion
      await _incrementDeviceConfigVersion(deviceId);
      await _syncSharedScreensForDevice(deviceId);
    } catch (e) {
      throw Exception('Failed to update screen: $e');
    }
  }

  @override
  Future<void> deleteScreen(String deviceId, String screenId) async {
    try {
      final screenRef = _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens')
          .doc(screenId);

      final batch = _firestore.batch();
      batch.delete(screenRef);
      await batch.commit();

      // Increment device configVersion
      await _incrementDeviceConfigVersion(deviceId);
      await _syncSharedScreensForDevice(deviceId);
    } catch (e) {
      throw Exception('Failed to delete screen: $e');
    }
  }

  /// Asset-pool fields, written only for IMAGE/ANIMATION screens so CLOCK and
  /// SENSOR documents stay free of fields the device would ignore.
  Map<String, dynamic> _poolFields(ScreenModel screen) {
    if (!screen.supportsAssetPool) return const {};
    return {
      'defaultAssetId': screen.defaultAssetId,
      'availableAssetIds': screen.availableAssetIds,
      'allowManualSwitch': screen.allowManualSwitch,
    };
  }

  @override
  Future<void> setScreenShared(
    String deviceId,
    String screenId,
    String? pairId,
    bool isShared,
  ) async {
    try {
      final screenRef = _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens')
          .doc(screenId);

      await screenRef.update({
        'isShared': isShared,
        'pairId': FieldValue.delete(),
        'sharedScreenId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _incrementDeviceConfigVersion(deviceId);
      await _syncSharedScreensForDevice(deviceId);
    } catch (e) {
      throw Exception('Failed to update screen sharing: $e');
    }
  }

  @override
  Future<void> reorderScreens(String deviceId, List<String> screenIds) async {
    try {
      final batch = _firestore.batch();
      final screensRef = _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens');

      for (int i = 0; i < screenIds.length; i++) {
        batch.update(screensRef.doc(screenIds[i]), {'order': i});
      }

      // In the batch, not after it: a commit that lands the new order but then
      // fails to bump the version leaves the device polling a version it has
      // already seen, so the reorder sits in Firestore unnoticed until some
      // unrelated edit happens to bump it.
      batch.update(_firestore.collection('devices').doc(deviceId), {
        'configVersion': FieldValue.increment(1),
      });

      await batch.commit();

      // Best-effort accelerator, same contract as _incrementDeviceConfigVersion.
      await _ringConfigDoorbell(deviceId);
    } catch (e) {
      throw Exception('Failed to reorder screens: $e');
    }
  }

  // Asset methods
  @override
  Future<List<AssetModel>> getAssetsByIds(List<String> assetIds) async {
    final uniqueIds = assetIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return const [];

    try {
      final snapshots = await Future.wait(
        uniqueIds.map((id) => _firestore.collection('assets').doc(id).get()),
      );

      return snapshots
          .where((snapshot) => snapshot.exists && snapshot.data() != null)
          .map((snapshot) => _assetFromFirestore(snapshot.id, snapshot.data()!))
          .toList();
    } catch (e) {
      throw Exception('Failed to get screen assets: $e');
    }
  }

  @override
  Future<List<AssetModel>> getUserAssets(String userId) async {
    try {
      // Canonical ownership supports private collection queries. Historical
      // userId-only assets require the explicit administrator migration.
      final snapshot = await _firestore
          .collection('assets')
          .where('ownerUid', isEqualTo: userId)
          .where('isDefault', isEqualTo: false)
          .get();
      return snapshot.docs
          .map((doc) => _assetFromFirestore(doc.id, doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Failed to get user assets: $e');
    }
  }

  @override
  Future<List<AssetModel>> getDefaultAssets() async {
    try {
      final querySnapshot = await _firestore
          .collection('assets')
          .where('isDefault', isEqualTo: true)
          .get();

      return querySnapshot.docs.map((doc) {
        return _assetFromFirestore(doc.id, doc.data());
      }).toList();
    } catch (e) {
      throw Exception('Failed to get default assets: $e');
    }
  }

  @override
  Future<AssetModel> createAsset(String userId, AssetModel asset) async {
    try {
      await _firestore.collection('assets').doc(asset.id).set({
        'name': asset.name,
        'type': asset.type.name.toUpperCase(),
        'ownerUid': userId,
        'width': 16,
        'height': 16,
        'tags': asset.tags,
        'isDefault': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        // A create writes a fresh document, so there is nothing to delete.
        ...buildAssetPixelFields(asset).values,
      });
      await _bumpDevicesUsingAsset(asset.id);
      return asset;
    } catch (e) {
      throw Exception('Failed to create asset: $e');
    }
  }

  @override
  Future<void> updateAsset(String assetId, AssetModel asset) async {
    try {
      // One update() call, so the new encoding and the removal of the fields it
      // replaces land together. A legacy animation edited here is rewritten in
      // the packed format as a side effect; nothing migrates in bulk.
      final fields = buildAssetPixelFields(asset);
      await _firestore.collection('assets').doc(assetId).update({
        'name': asset.name,
        'tags': asset.tags,
        'type': asset.type.name.toUpperCase(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        ...fields.values,
        for (final name in fields.obsoleteFieldNames) name: FieldValue.delete(),
      });
      await _bumpDevicesUsingAsset(assetId);
      final uid = _auth.currentUser?.uid;
      if (uid != null) await syncSharedScreens(uid);
    } catch (e) {
      throw Exception('Failed to update asset: $e');
    }
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    try {
      final assetRef = _firestore.collection('assets').doc(assetId);
      final assetSnapshot = await assetRef.get();
      final assetData = assetSnapshot.data();

      if (!assetSnapshot.exists || assetData == null) {
        final uid = _auth.currentUser?.uid;
        if (uid != null) await syncSharedScreens(uid);
        return;
      }
      if (assetData['isDefault'] == true) {
        throw Exception('Default assets cannot be deleted');
      }

      final currentUserId = _auth.currentUser?.uid;
      final ownerId =
          assetData['ownerUid'] as String? ?? assetData['userId'] as String?;
      if (currentUserId == null || ownerId != currentUserId) {
        throw Exception('You can only delete your own assets');
      }

      final screensUsingAsset = await _getScreensUsingAsset(
        currentUserId,
        assetId,
      );
      final affectedDeviceIds = screensUsingAsset
          .map((screen) => screen.reference.parent.parent?.id)
          .whereType<String>()
          .toSet();

      // Delete the asset, clean every screen reference, and bump each affected
      // device in one commit. A failed commit therefore cannot leave screens
      // pointing at an asset that was already removed.
      final batch = _firestore.batch();
      for (final screen in screensUsingAsset) {
        final data = screen.data();
        final references = _assetReferencesFromScreenData(
          data,
        ).without(assetId);
        batch.update(screen.reference, {
          'assetId': references.assetId ?? FieldValue.delete(),
          'defaultAssetId': references.defaultAssetId ?? FieldValue.delete(),
          'availableAssetIds': references.availableAssetIds,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }
      for (final deviceId in affectedDeviceIds) {
        batch.update(_firestore.collection('devices').doc(deviceId), {
          'configVersion': FieldValue.increment(1),
        });
      }
      batch.delete(assetRef);
      await batch.commit();

      // The Firestore version is authoritative. This best-effort doorbell just
      // asks online devices to read it sooner than their periodic poll.
      await Future.wait(affectedDeviceIds.map(_ringConfigDoorbell));
      await syncSharedScreens(currentUserId);
    } catch (e) {
      throw Exception('Failed to delete asset: $e');
    }
  }

  // Pairing is authoritative in RTDB; no cross-database ACL mirroring.
  @override
  Future<PairingModel> getPairing(String userId) =>
      _pairing(userId).getPairing();
  @override
  Stream<PairingModel> watchPairing(String userId) =>
      _pairing(userId).watchPairing();
  @override
  Stream<List<PairingInvite>> watchPairingInvites(
    String userId, {
    required bool incoming,
  }) => _pairing(userId).watchInvites(incoming);
  @override
  Future<List<DeviceModel>> getPairableDevices(String userId) =>
      getDevices(userId);

  @override
  Stream<Map<String, dynamic>> watchPairingAcknowledgment(
    String pairId,
    String receiverDeviceId,
  ) => _database
      .ref('pairing/acks/$pairId/$receiverDeviceId')
      .onValue
      .map((e) => pairingMap(e.snapshot.value));
  @override
  Future<void> sendPairingInvite(
    String userId,
    String targetEmail,
    String deviceId,
  ) => _pairing(userId).sendInvite(targetEmail, deviceId);
  @override
  Future<void> acceptPairingInvite(
    String userId,
    String inviteId,
    String deviceId,
  ) => _pairing(userId).acceptInvite(inviteId, deviceId);
  @override
  Future<void> resolvePairingInvite(
    String userId,
    String inviteId,
    String status,
  ) => _pairing(userId).resolveInvite(inviteId, status);
  @override
  Future<void> unpair(String userId) => _pairing(userId).unpair();

  Future<void> _syncSharedScreensForDevice(String deviceId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _queueSharedCatalog(uid, deviceId: deviceId);
  }

  @override
  Future<void> syncSharedScreens(String userId) async {
    await _queueSharedCatalog(userId);
  }

  Future<void> _queueSharedCatalog(String uid, {String? deviceId}) =>
      _sharedCatalogQueue.run(
        '${_database.app.name}/${_database.databaseURL}/$uid',
        () async {
          final pair = await getPairing(uid);
          if (deviceId == null || pair.deviceId == deviceId) {
            await _syncSharedCatalog(uid, pair);
          }
        },
      );

  Future<void> _syncSharedCatalog(String uid, PairingModel pair) async {
    if (!pair.isPaired || pair.deviceId == null) return;
    final device = _firestore.collection('devices').doc(pair.deviceId!);
    const server = GetOptions(source: Source.server);
    final before =
        (await device.get(server)).data()?['configVersion'] as int? ?? 0;
    final snapshot = await device
        .collection('screens')
        .orderBy('order')
        .get(server);
    final screens = snapshot.docs
        .map((d) => _screenFromFirestore(d.id, d.data()))
        .toList();
    final ids = screens
        .where((s) => s.isShared && s.supportsAssetPool)
        .map(
          (s) =>
              s.defaultAssetId ??
              s.assetId ??
              (s.availableAssetIds.isEmpty ? null : s.availableAssetIds.first),
        )
        .whereType<String>()
        .toList();
    final docs = await Future.wait(
      ids.toSet().map(
        (id) => _firestore.collection('assets').doc(id).get(server),
      ),
    );
    final assets = docs
        .where((d) => d.exists)
        .map((d) => _assetFromFirestore(d.id, d.data()!))
        .toList();
    final after =
        (await device.get(server)).data()?['configVersion'] as int? ?? 0;
    if (before != after)
      throw StateError(
        'Screen configuration changed during sharing. Refresh and try again.',
      );
    await SharedScreensService(
      FirebasePairingStore(_database),
      uid,
    ).sync(pair, screens, assets, sourceVersion: after);
  }

  @override
  Stream<List<SharedScreenModel>> watchSharedScreens(
    String pairId,
    String ownerUid,
  ) => SharedScreensService(
    FirebasePairingStore(_database),
    _auth.currentUser?.uid ?? '',
  ).watch(pairId, ownerUid);

  // RTDB methods
  @override
  Stream<Map<String, dynamic>> watchDevicePresence(String deviceId) {
    final presenceRef = _database.ref('presence/$deviceId');
    return presenceRef.onValue.map((event) {
      if (event.snapshot.value == null) {
        return {'online': false};
      }
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      return Map<String, dynamic>.from(data);
    });
  }

  @override
  Stream<Map<String, dynamic>> watchDeviceTelemetry(String deviceId) {
    final telemetryRef = _database.ref('telemetry/$deviceId');
    return telemetryRef.onValue.map((event) {
      if (event.snapshot.value == null) {
        return {};
      }
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      return Map<String, dynamic>.from(data);
    });
  }

  @override
  Future<void> sendCommand(
    String deviceId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    try {
      // One child per command, keyed by a push id. The device walks the
      // children of /commands/{deviceId} and acknowledges a command by
      // removing /commands/{deviceId}/{commandId}, so writing the fields onto
      // the device node itself made 'type' and 'payload' look like two
      // commands, left nothing for the device to delete, and threw away any
      // command still queued.
      final commandRef = _database.ref('commands/$deviceId').push();
      await commandRef.set({
        'type': type,
        'payload': payload,
        'timestamp': ServerValue.timestamp,
        'status': 'PENDING',
      });
    } catch (e) {
      throw Exception('Failed to send command: $e');
    }
  }

  // Helper methods
  UserModel? _userFromFirebaseUser(User? user) {
    if (user == null) return null;
    return UserModel(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }

  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return Exception('The password provided is too weak.');
      case 'email-already-in-use':
        return Exception('An account already exists for that email.');
      case 'invalid-email':
        return Exception('The email address is invalid.');
      case 'user-disabled':
        return Exception('This user account has been disabled.');
      case 'user-not-found':
        return Exception('No user found for that email.');
      case 'wrong-password':
        return Exception('Wrong password provided.');
      default:
        return Exception('Authentication error: ${e.message}');
    }
  }

  DeviceModel _deviceFromFirestore(String id, Map<String, dynamic> data) {
    return DeviceModel(
      id: id,
      name: data['name'] ?? 'Unknown Device',
      isOnline: data['isOnline'] ?? false,
      hasSensor: data['hasSensor'] ?? false,
      userId: data['userId'],
      timezone: data['timezone'],
      tzPosix: data['tzPosix'],
      brightness: (data['brightness'] as num?)?.toInt(),
      sleepMode: _sleepModeFromFirestore(data['sleepMode']),
    );
  }

  Map<String, dynamic> _sleepModeToMap(SleepSchedule sleep) {
    return {
      'enabled': sleep.enabled,
      'startMinute': sleep.startMinute,
      'endMinute': sleep.endMinute,
      'brightness': sleep.brightness,
    };
  }

  /// Missing or malformed maps come back null, which the rest of the stack
  /// reads as "no schedule set yet" rather than a disabled one.
  SleepSchedule? _sleepModeFromFirestore(dynamic raw) {
    if (raw is! Map) return null;
    return SleepSchedule(
      enabled: raw['enabled'] == true,
      startMinute:
          (raw['startMinute'] as num?)?.toInt() ??
          SleepSchedule.defaultStartMinute,
      endMinute:
          (raw['endMinute'] as num?)?.toInt() ?? SleepSchedule.defaultEndMinute,
      brightness:
          (raw['brightness'] as num?)?.toInt() ??
          SleepSchedule.defaultBrightness,
    );
  }

  ScreenModel _screenFromFirestore(String id, Map<String, dynamic> data) {
    return ScreenModel(
      id: id,
      type: _screenTypeFromString(data['type'] ?? 'clock'),
      name: data['name'],
      enabled: data['enabled'] ?? true,
      isShared: data['isShared'] ?? false,
      assetId: data['assetId'],
      config: data['config'] != null
          ? Map<String, dynamic>.from(data['config'])
          : null,
      previewData: data['previewData'] != null
          ? List<List<int>>.from(
              (data['previewData'] as List).map((row) => List<int>.from(row)),
            )
          : null,
      defaultAssetId: data['defaultAssetId'],
      availableAssetIds: data['availableAssetIds'] != null
          ? List<String>.from(data['availableAssetIds'] as List)
          : const [],
      allowManualSwitch: data['allowManualSwitch'] ?? true,
    );
  }

  ScreenType _screenTypeFromString(String type) {
    switch (type) {
      case 'clock':
        return ScreenType.clock;
      case 'image':
        return ScreenType.image;
      case 'animation':
        return ScreenType.animation;
      case 'sensor':
        return ScreenType.sensor;
      case 'game':
        return ScreenType.game;
      default:
        return ScreenType.clock;
    }
  }

  AssetModel _assetFromFirestore(String id, Map<String, dynamic> data) {
    final type = (data['type'] as String?)?.toLowerCase() == 'animation'
        ? AssetType.animation
        : AssetType.image;

    final frames = type == AssetType.animation
        ? _animationFramesFromFirestore(data)
        : null;

    // Convert sparse format back to full 16x16 grid for UI
    List<List<int>>? pixelData;

    if (frames != null && frames.isNotEmpty) {
      // Thumbnails and any caller that predates animations read pixelData, so
      // an animation still exposes its first frame there.
      pixelData = frames.first.pixels;
    } else if (data['pixelsPacked'] != null) {
      // SPARSE_PACKED_V1: "IIRRGGBB" groups in a single string
      pixelData = _convertFromPackedFormat(data['pixelsPacked'] as String);
    } else if (data['pixels'] != null) {
      // Sparse format: [{"index": i, "color": c}, ...] or legacy [[i, c], ...]
      pixelData = _convertFromSparseFormat(data['pixels'] as List);
    } else if (data['pixelData'] != null) {
      // Legacy format: full grid (for backward compatibility)
      pixelData = List<List<int>>.from(
        (data['pixelData'] as List).map((row) => List<int>.from(row)),
      );
    }

    return AssetModel(
      id: id,
      name: data['name'] ?? 'Unnamed Asset',
      type: type,
      tags: data['tags'] != null ? List<String>.from(data['tags']) : [],
      pixelData: pixelData,
      frames: frames != null && frames.isNotEmpty ? frames : null,
      isDefault: data['isDefault'] ?? false,
      createdAt: data['createdAt']?.toDate(),
    );
  }

  /// Reads an animation in either the packed encoding or the legacy one.
  ///
  /// Returns null when the document carries neither, which is how an asset
  /// typed ANIMATION but holding a single image still opens in the editor.
  List<AnimationFrameModel>? _animationFramesFromFirestore(
    Map<String, dynamic> data,
  ) {
    if (data['basePixelsPacked'] != null) {
      return AnimationCodec.decode(
        basePixelsPacked: data['basePixelsPacked'] as String? ?? '',
        frameDeltasPacked: data['frameDeltasPacked'] != null
            ? List<String>.from(data['frameDeltasPacked'] as List)
            : const [],
        frameDurationsMs: data['frameDurationsMs'] != null
            ? List<int>.from(data['frameDurationsMs'] as List)
            : const [],
      );
    }

    if (data['frames'] != null) {
      return AnimationCodec.decodeLegacy(
        basePixels: data['basePixels'] as List? ?? const [],
        legacyFrames: data['frames'] as List,
      );
    }

    return null;
  }

  Future<void> _incrementDeviceConfigVersion(String deviceId) async {
    // FieldValue.increment rather than a read-then-write: two edits made close
    // together used to read the same version and both write n+1, so one screen
    // change was silently dropped and never reached the device.
    await _firestore.collection('devices').doc(deviceId).update({
      'configVersion': FieldValue.increment(1),
    });
    await _ringConfigDoorbell(deviceId);
  }

  /// Ticks the RTDB node the device watches every few seconds. The value is a
  /// bare counter - the device only reacts to it *changing*, then re-reads the
  /// authoritative configVersion from Firestore - so this never has to agree
  /// with the Firestore field. Without it the device waits out its 60s poll.
  ///
  /// Deliberately swallows failures: the doorbell is an accelerator, and the
  /// 60s poll still delivers the change. A screen edit must not surface as an
  /// error just because RTDB was unreachable.
  Future<void> _ringConfigDoorbell(String deviceId) async {
    try {
      await _database
          .ref('config/$deviceId/configVersion')
          .set(ServerValue.increment(1));
    } catch (e) {
      // Logged, not rethrown: the Firestore poll still delivers the change.
      debugPrint(
        'Config doorbell failed for $deviceId (device will still '
        'update on its 60s poll): $e',
      );
    }
  }

  /// Assets carry no device context, so find the current user's mapped devices
  /// and bump each one with a screen that references the asset. Reading the
  /// short playlist below each mapped device matches the Firestore ownership
  /// model and avoids a cross-user collection-group query that security rules
  /// cannot safely authorize.
  Future<void> _bumpDevicesUsingAsset(String assetId) async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      final matchingScreens = await _getScreensUsingAsset(
        currentUserId,
        assetId,
      );
      final deviceIds = matchingScreens
          .map((screen) => screen.reference.parent.parent?.id)
          .whereType<String>()
          .toSet();
      for (final id in deviceIds) {
        await _incrementDeviceConfigVersion(id);
      }
    } catch (e) {
      // Never fail the asset save over the notification, but do say so:
      // swallowing this would look exactly like the stale-device bug this
      // helper prevents.
      debugPrint(
        'Could not notify devices using asset $assetId; they will '
        'show stale pixels until another edit bumps them: $e',
      );
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getScreensUsingAsset(String userId, String assetId) async {
    final deviceMappings = await _firestore
        .collection('users')
        .doc(userId)
        .collection('devices')
        .get();
    final screenSnapshots =
        await loadOwnedDeviceMappings<
          QueryDocumentSnapshot<Map<String, dynamic>>,
          QuerySnapshot<Map<String, dynamic>>
        >(
          mappings: deviceMappings.docs,
          userId: userId,
          deviceId: (mapping) => mapping.id,
          readAccess: (id) async =>
              (await _database.ref('deviceAccess/$id').get()).value,
          load: (mapping) => _firestore
              .collection('devices')
              .doc(mapping.id)
              .collection('screens')
              .get(),
        );

    return screenSnapshots
        .expand((snapshot) => snapshot.docs)
        .where(
          (screen) =>
              _assetReferencesFromScreenData(screen.data()).contains(assetId),
        )
        .toList(growable: false);
  }

  ScreenAssetReferences _assetReferencesFromScreenData(
    Map<String, dynamic> data,
  ) {
    final rawAvailableAssetIds = data['availableAssetIds'];
    return ScreenAssetReferences(
      assetId: data['assetId'] as String?,
      defaultAssetId: data['defaultAssetId'] as String?,
      availableAssetIds: rawAvailableAssetIds is List
          ? rawAvailableAssetIds.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  /// Converts SPARSE_PACKED_V1 back to a full 16x16 grid, with alpha forced to
  /// 255 to match [_convertFromSparseFormat].
  List<List<int>> _convertFromPackedFormat(String packed) {
    final grid = List.generate(16, (_) => List.filled(16, 0));
    if (packed.isEmpty || packed.length % 8 != 0) return grid;

    for (int i = 0; i < packed.length; i += 8) {
      final index = int.tryParse(packed.substring(i, i + 2), radix: 16);
      final rgb888 = int.tryParse(packed.substring(i + 2, i + 8), radix: 16);
      if (index == null || rgb888 == null || index < 0 || index >= 256) {
        continue;
      }

      final y = index ~/ 16;
      final x = index % 16;
      grid[y][x] = 0xFF000000 | rgb888;
    }

    return grid;
  }

  /// Converts sparse format [{"index": i, "color": c}, ...] back to full 16x16 grid
  /// Supports both array-of-maps format (new) and array-of-arrays format (legacy)
  /// where index = y*16 + x and color is RGB888 (converted to ARGB with alpha=255)
  List<List<int>> _convertFromSparseFormat(List<dynamic> sparsePixels) {
    // Initialize 16x16 grid with zeros (black/transparent)
    final grid = List.generate(16, (_) => List.filled(16, 0));

    for (final pixelEntry in sparsePixels) {
      int? index;
      int? rgb888;

      // Try array-of-maps format first (new format)
      if (pixelEntry is Map) {
        index = pixelEntry['index'] as int?;
        rgb888 = pixelEntry['color'] as int?;
      }
      // Fall back to array-of-arrays format (legacy)
      else if (pixelEntry is List && pixelEntry.length >= 2) {
        index = pixelEntry[0] as int?;
        rgb888 = pixelEntry[1] as int?;
      }

      if (index != null && rgb888 != null && index >= 0 && index < 256) {
        final y = index ~/ 16;
        final x = index % 16;

        if (y < 16 && x < 16) {
          // Convert RGB888 to ARGB (add alpha channel = 255)
          final argb = 0xFF000000 | rgb888;
          grid[y][x] = argb;
        }
      }
    }

    return grid;
  }
}
