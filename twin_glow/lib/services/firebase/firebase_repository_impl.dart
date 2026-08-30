import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_repository.dart';
import '../../core/models/device_model.dart';
import '../../core/models/screen_model.dart';
import '../../core/models/asset_model.dart';
import '../../core/models/user_model.dart';
import '../../core/models/pairing_model.dart';

class FirebaseRepositoryImpl implements FirebaseRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Auth methods
  @override
  Future<UserModel?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
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

      // For each deviceId in mappings, fetch the device metadata from /devices/{deviceId}
      final devices = <DeviceModel>[];
      for (final mapDoc in mappingSnapshot.docs) {
        final deviceId = mapDoc.id;
        final deviceDoc = await _firestore.collection('devices').doc(deviceId).get();
        if (!deviceDoc.exists) continue;

        // Prefer user's name override if present
        final data = deviceDoc.data()!;
        final mapData = mapDoc.data();
        final name = (mapData['nameOverride'] as String?) ?? data['name'] as String? ?? '';
        var device = _deviceFromFirestore(
          deviceId,
          {
            ...data,
            'name': name,
            // Include hasSensor and other metadata from /devices
            'hasSensor': data['hw'] != null && (data['hw']['bme680'] == true),
          },
        );
        // Online status from RTDB
        final presenceRef = _database.ref('presence/$deviceId');
        final snapshot = await presenceRef.get();
        if (snapshot.exists) {
          final presenceData = snapshot.value as Map<dynamic, dynamic>?;
          device = device.copyWith(isOnline: presenceData?['online'] == true);
        }

        devices.add(device);
      }
      return devices;
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
      final existingScreens = await screensRef.orderBy('order', descending: true).limit(1).get();
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

      return screen;
    } catch (e) {
      throw Exception('Failed to create screen: $e');
    }
  }

  @override
  Future<void> updateScreen(String deviceId, String screenId, ScreenModel screen) async {
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

      // Firestore has no foreign keys, so the shared-screen pointer would
      // dangle if we only deleted the screen. The screen doc records where its
      // pointer lives, which makes the cleanup a direct delete.
      final snapshot = await screenRef.get();
      final data = snapshot.data();
      final pairId = data?['pairId'] as String?;
      final sharedScreenId = data?['sharedScreenId'] as String?;

      final batch = _firestore.batch();
      batch.delete(screenRef);
      if (pairId != null && sharedScreenId != null) {
        batch.delete(_sharedScreenRef(pairId, sharedScreenId));
      }
      await batch.commit();

      // Increment device configVersion
      await _incrementDeviceConfigVersion(deviceId);
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

  DocumentReference<Map<String, dynamic>> _sharedScreenRef(
    String pairId,
    String sharedScreenId,
  ) {
    return _firestore
        .collection('pairs')
        .doc(pairId)
        .collection('sharedScreens')
        .doc(sharedScreenId);
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

      // Without a pair there is nowhere to point, so record the intent on the
      // screen and stop. Sharing becomes effective once a pair exists.
      if (pairId == null || pairId.isEmpty) {
        await screenRef.update({
          'isShared': isShared,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        await _incrementDeviceConfigVersion(deviceId);
        return;
      }

      // Deterministic id keeps the operation idempotent - re-sharing the same
      // screen overwrites its pointer instead of creating a duplicate.
      final sharedScreenId = '${deviceId}_$screenId';
      final batch = _firestore.batch();

      if (isShared) {
        final snapshot = await screenRef.get();
        batch.update(screenRef, {
          'isShared': true,
          'pairId': pairId,
          'sharedScreenId': sharedScreenId,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        // The pointer carries no content - only which screen is shared.
        batch.set(_sharedScreenRef(pairId, sharedScreenId), {
          'deviceId': deviceId,
          'screenId': screenId,
          'ownerUid': _auth.currentUser?.uid,
          'type': (snapshot.data()?['type'] as String? ?? 'image').toUpperCase(),
          'sharedAt': Timestamp.fromDate(DateTime.now()),
        });
      } else {
        batch.update(screenRef, {
          'isShared': false,
          'pairId': FieldValue.delete(),
          'sharedScreenId': FieldValue.delete(),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        batch.delete(_sharedScreenRef(pairId, sharedScreenId));
      }

      await batch.commit();
      await _incrementDeviceConfigVersion(deviceId);
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

      await batch.commit();

      // Increment device configVersion
      await _incrementDeviceConfigVersion(deviceId);
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
      // Support both 'userId' (legacy) and 'ownerUid' (new format)
      final querySnapshot = await _firestore
          .collection('assets')
          .where('ownerUid', isEqualTo: userId)
          .where('isDefault', isEqualTo: false)
          .get();

      // Also query legacy format for backward compatibility
      final legacySnapshot = await _firestore
          .collection('assets')
          .where('userId', isEqualTo: userId)
          .where('isDefault', isEqualTo: false)
          .get();

      final allDocs = <String, dynamic>{};
      for (var doc in querySnapshot.docs) {
        allDocs[doc.id] = doc.data();
      }
      for (var doc in legacySnapshot.docs) {
        if (!allDocs.containsKey(doc.id)) {
          allDocs[doc.id] = doc.data();
        }
      }

      return allDocs.entries.map((entry) {
        print("entry: ${entry.value}");
        return _assetFromFirestore(entry.key, entry.value);
      }).toList();
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
      // Packed format: one string instead of one Firestore map per pixel.
      // The old per-pixel encoding made a 78-pixel image a ~23KB document,
      // which the device's Firebase client could not buffer - it returned an
      // empty body and the screen rendered black.
      final packedPixels = _convertToPackedFormat(asset.pixelData);

      await _firestore.collection('assets').doc(asset.id).set({
        'name': asset.name,
        'type': asset.type.name.toUpperCase(),
        'ownerUid': userId,
        'width': 16,
        'height': 16,
        'encoding': 'SPARSE_PACKED_V1',
        'pixelsPacked': packedPixels,
        'tags': asset.tags,
        'isDefault': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
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
      final packedPixels = _convertToPackedFormat(asset.pixelData);

      await _firestore.collection('assets').doc(assetId).update({
        'name': asset.name,
        'tags': asset.tags,
        'encoding': 'SPARSE_PACKED_V1',
        'pixelsPacked': packedPixels,
        // Deleting the legacy array is what actually shrinks the document.
        // Leaving it behind keeps the doc too large for the device to fetch,
        // so re-saving an asset from the app doubles as its migration.
        'pixels': FieldValue.delete(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      await _bumpDevicesUsingAsset(assetId);
    } catch (e) {
      throw Exception('Failed to update asset: $e');
    }
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    try {
      await _firestore.collection('assets').doc(assetId).delete();
      // The screen docs still carry the id, so the lookup works after the
      // delete and the device gets told to drop the cached pixels.
      await _bumpDevicesUsingAsset(assetId);
    } catch (e) {
      throw Exception('Failed to delete asset: $e');
    }
  }

  // Pairing methods
  @override
  Future<PairingModel> getPairing(String userId) async {
    try {
      // Query pairs where userA or userB equals userId
      final pairsQueryA = await _firestore
          .collection('pairs')
          .where('userA', isEqualTo: userId)
          .limit(1)
          .get();

      final pairsQueryB = await _firestore
          .collection('pairs')
          .where('userB', isEqualTo: userId)
          .limit(1)
          .get();

      PairingModel? pairing;
      
      if (pairsQueryA.docs.isNotEmpty) {
        final pairData = pairsQueryA.docs.first.data();
        final otherUserId = pairData['userB'] as String?;
        if (otherUserId != null) {
          final otherUser = await _getUserById(otherUserId);
          pairing = PairingModel(
            pairId: pairsQueryA.docs.first.id,
            pairedUserId: otherUserId,
            pairedUserName: otherUser?.displayName ?? otherUser?.email,
            sharedScreensCount: await _countSharedScreens(userId, otherUserId),
          );
        }
      } else if (pairsQueryB.docs.isNotEmpty) {
        final pairData = pairsQueryB.docs.first.data();
        final otherUserId = pairData['userA'] as String?;
        if (otherUserId != null) {
          final otherUser = await _getUserById(otherUserId);
          pairing = PairingModel(
            pairId: pairsQueryB.docs.first.id,
            pairedUserId: otherUserId,
            pairedUserName: otherUser?.displayName ?? otherUser?.email,
            sharedScreensCount: await _countSharedScreens(userId, otherUserId),
          );
        }
      }

      return pairing ?? PairingModel();
    } catch (e) {
      throw Exception('Failed to get pairing: $e');
    }
  }

  @override
  Future<void> sendPairingInvite(String userId, String targetEmail) async {
    try {
      // Find user by email
      final usersQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .limit(1)
          .get();

      if (usersQuery.docs.isEmpty) {
        throw Exception('User not found');
      }

      final targetUserId = usersQuery.docs.first.id;

      // Create invite document
      await _firestore.collection('pairingInvites').add({
        'fromUserId': userId,
        'toUserId': targetUserId,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Failed to send pairing invite: $e');
    }
  }

  @override
  Future<void> acceptPairingInvite(String userId, String inviteId) async {
    try {
      final inviteDoc = await _firestore
          .collection('pairingInvites')
          .doc(inviteId)
          .get();

      if (!inviteDoc.exists) {
        throw Exception('Invite not found');
      }

      final inviteData = inviteDoc.data()!;
      final fromUserId = inviteData['fromUserId'] as String;

      if (fromUserId == userId) {
        throw Exception('Cannot accept own invite');
      }

      // Create pair document
      final pairId = '${fromUserId}_$userId';
      await _firestore.collection('pairs').doc(pairId).set({
        'userA': fromUserId,
        'userB': userId,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });

      // Update user documents with pairId
      await _firestore.collection('users').doc(fromUserId).update({
        'pairId': pairId,
      });
      await _firestore.collection('users').doc(userId).update({
        'pairId': pairId,
      });

      // Delete invite
      await inviteDoc.reference.delete();
    } catch (e) {
      throw Exception('Failed to accept pairing invite: $e');
    }
  }

  @override
  Future<void> unpair(String userId) async {
    try {
      final pairing = await getPairing(userId);
      if (!pairing.isPaired || pairing.pairedUserId == null) {
        return;
      }

      // Find and delete pair document
      final pairsQueryA = await _firestore
          .collection('pairs')
          .where('userA', isEqualTo: userId)
          .limit(1)
          .get();

      final pairsQueryB = await _firestore
          .collection('pairs')
          .where('userB', isEqualTo: userId)
          .limit(1)
          .get();

      if (pairsQueryA.docs.isNotEmpty) {
        await pairsQueryA.docs.first.reference.delete();
      } else if (pairsQueryB.docs.isNotEmpty) {
        await pairsQueryB.docs.first.reference.delete();
      }

      // Remove pairId from user documents
      await _firestore.collection('users').doc(userId).update({
        'pairId': FieldValue.delete(),
      });
      if (pairing.pairedUserId != null) {
        await _firestore.collection('users').doc(pairing.pairedUserId!).update({
          'pairId': FieldValue.delete(),
        });
      }
    } catch (e) {
      throw Exception('Failed to unpair: $e');
    }
  }

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
  Future<void> sendCommand(String deviceId, String type, Map<String, dynamic> payload) async {
    try {
      final commandRef = _database.ref('commands/$deviceId');
      await commandRef.set({
        'type': type,
        'payload': payload,
        'timestamp': ServerValue.timestamp,
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
          (raw['brightness'] as num?)?.toInt() ?? SleepSchedule.defaultBrightness,
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
              (data['previewData'] as List).map((row) => List<int>.from(row))
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
    // Convert sparse format back to full 16x16 grid for UI
    List<List<int>>? pixelData;
    
    if (data['pixelsPacked'] != null) {
      // SPARSE_PACKED_V1: "IIRRGGBB" groups in a single string
      pixelData = _convertFromPackedFormat(data['pixelsPacked'] as String);
    } else if (data['pixels'] != null) {
      // Sparse format: [{"index": i, "color": c}, ...] or legacy [[i, c], ...]
      pixelData = _convertFromSparseFormat(data['pixels'] as List);
    } else if (data['pixelData'] != null) {
      // Legacy format: full grid (for backward compatibility)
      pixelData = List<List<int>>.from(
        (data['pixelData'] as List).map((row) => List<int>.from(row))
      );
    }
    
    return AssetModel(
      id: id,
      name: data['name'] ?? 'Unnamed Asset',
      type: (data['type'] as String?)?.toLowerCase() == 'animation' 
          ? AssetType.animation 
          : AssetType.image,
      tags: data['tags'] != null ? List<String>.from(data['tags']) : [],
      pixelData: pixelData,
      isDefault: data['isDefault'] ?? false,
      createdAt: data['createdAt']?.toDate(),
    );
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
      debugPrint('Config doorbell failed for $deviceId (device will still '
          'update on its 60s poll): $e');
    }
  }

  /// Assets carry no device context, so find the screens pointing at one and
  /// bump every device that shows it. Without this an asset edit never bumped
  /// anything at all and the panel kept rendering the old pixels indefinitely.
  ///
  /// A screen can reference an asset three ways since the asset pool moved onto
  /// the screen document: the legacy `assetId`, the pool's `defaultAssetId`, or
  /// any entry of `availableAssetIds`. Firestore cannot OR across different
  /// fields in one query, so this runs all three and unions the results -
  /// checking only `assetId` would silently miss every pooled image.
  ///
  /// Each query needs its own collection-group index on `screens`.
  ///
  /// Not covered: an asset reached solely through a shared-screen pointer
  /// (pairs/{pairId}/sharedScreens), which needs a pair to device traversal
  /// that does not exist yet.
  Future<void> _bumpDevicesUsingAsset(String assetId) async {
    try {
      final screens = _firestore.collectionGroup('screens');
      final results = await Future.wait([
        screens.where('assetId', isEqualTo: assetId).get(),
        screens.where('defaultAssetId', isEqualTo: assetId).get(),
        screens.where('availableAssetIds', arrayContains: assetId).get(),
      ]);
      final deviceIds = results
          .expand((r) => r.docs)
          .map((d) => d.reference.parent.parent?.id)
          .whereType<String>()
          .toSet();
      for (final id in deviceIds) {
        await _incrementDeviceConfigVersion(id);
      }
    } catch (e) {
      // Never fail the asset save over the notification - but do say so. A
      // missing collection-group index on screens.assetId lands here, and
      // silently swallowing it would look exactly like the bug this fixes.
      debugPrint('Could not notify devices using asset $assetId; they will '
          'show stale pixels until another edit bumps them: $e');
    }
  }

  Future<UserModel?> _getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      return UserModel(
        id: userId,
        email: data['email'] ?? '',
        displayName: data['displayName'],
      );
    } catch (e) {
      return null;
    }
  }

  Future<int> _countSharedScreens(String userId1, String userId2) async {
    // Count screens that are shared between these two users
    // This is a simplified implementation - in reality, you'd need to check
    // sharedScreenRef and pairId relationships
    try {
      // Get all devices for user1
      final devices1 = await getDevices(userId1);
      
      int count = 0;
      for (var device in devices1) {
        final screens = await getScreens(device.id);
        count += screens.where((s) => s.isShared).length;
      }
      
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Converts a full 16x16 grid to SPARSE_PACKED_V1: one string of fixed-width
  /// 8-character groups, "IIRRGGBB" per non-black pixel, where II is the index
  /// (y*16 + x, 0-255) and RRGGBB is the colour.
  ///
  /// This exists because the previous per-pixel map format produced Firestore
  /// documents around 23KB, which the device's Firebase client silently failed
  /// to buffer. The packed form is roughly 1KB for the same image.
  String _convertToPackedFormat(List<List<int>>? pixelData) {
    if (pixelData == null || pixelData.isEmpty) return '';

    final buffer = StringBuffer();

    for (int y = 0; y < pixelData.length && y < 16; y++) {
      final row = pixelData[y];
      for (int x = 0; x < row.length && x < 16; x++) {
        final color = row[x];
        // Skip black pixels (0 or transparent)
        if (color != 0) {
          // Convert ARGB to RGB888 (remove alpha channel)
          final rgb888 = color & 0xFFFFFF;
          final index = y * 16 + x;
          buffer.write(index.toRadixString(16).padLeft(2, '0'));
          buffer.write(rgb888.toRadixString(16).padLeft(6, '0'));
        }
      }
    }

    return buffer.toString();
  }

  /// Converts SPARSE_PACKED_V1 back to a full 16x16 grid, with alpha forced to
  /// 255 to match [_convertFromSparseFormat].
  List<List<int>> _convertFromPackedFormat(String packed) {
    final grid = List.generate(16, (_) => List.filled(16, 0));
    if (packed.isEmpty || packed.length % 8 != 0) return grid;

    for (int i = 0; i < packed.length; i += 8) {
      final index = int.tryParse(packed.substring(i, i + 2), radix: 16);
      final rgb888 = int.tryParse(packed.substring(i + 2, i + 8), radix: 16);
      if (index == null || rgb888 == null || index < 0 || index >= 256) continue;

      final y = index ~/ 16;
      final x = index % 16;
      grid[y][x] = 0xFF000000 | rgb888;
    }

    return grid;
  }

  /// Converts full 16x16 grid to sparse format: [{"index": i, "color": c}, ...]
  /// where index = y*16 + x (0-255) and color is RGB888 (0xRRGGBB)
  /// Uses array of maps format which is more Firestore-friendly than nested arrays
  ///
  /// Retained only to read assets written before SPARSE_PACKED_V1; new writes
  /// go through [_convertToPackedFormat].
  List<Map<String, int>> _convertToSparseFormat(List<List<int>>? pixelData) {
    if (pixelData == null || pixelData.isEmpty) return [];
    
    final sparsePixels = <Map<String, int>>[];
    
    for (int y = 0; y < pixelData.length && y < 16; y++) {
      final row = pixelData[y];
      for (int x = 0; x < row.length && x < 16; x++) {
        final color = row[x];
        // Skip black pixels (0 or transparent)
        if (color != 0) {
          // Convert ARGB to RGB888 (remove alpha channel)
          final rgb888 = color & 0xFFFFFF;
          final index = y * 16 + x;
          sparsePixels.add({
            'index': index,
            'color': rgb888,
          });
        }
      }
    }
    
    return sparsePixels;
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
