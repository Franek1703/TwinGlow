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
          'createdAt': FieldValue.serverTimestamp(),
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
        'createdAt': FieldValue.serverTimestamp(),
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
      final currentData = await deviceRef.get();
      final currentVersion = currentData.data()?['configVersion'] ?? 0;

      await deviceRef.update({
        'name': device.name,
        'hasSensor': device.hasSensor,
        'configVersion': currentVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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
        'createdAt': FieldValue.serverTimestamp(),
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
        'updatedAt': FieldValue.serverTimestamp(),
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
      await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('screens')
          .doc(screenId)
          .delete();

      // Increment device configVersion
      await _incrementDeviceConfigVersion(deviceId);
    } catch (e) {
      throw Exception('Failed to delete screen: $e');
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
  Future<List<AssetModel>> getUserAssets(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('assets')
          .where('userId', isEqualTo: userId)
          .where('isDefault', isEqualTo: false)
          .get();

      return querySnapshot.docs.map((doc) {
        return _assetFromFirestore(doc.id, doc.data());
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
      await _firestore.collection('assets').doc(asset.id).set({
        'name': asset.name,
        'type': asset.type.name,
        'userId': userId,
        'tags': asset.tags,
        'pixelData': asset.pixelData,
        'isDefault': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return asset;
    } catch (e) {
      throw Exception('Failed to create asset: $e');
    }
  }

  @override
  Future<void> updateAsset(String assetId, AssetModel asset) async {
    try {
      await _firestore.collection('assets').doc(assetId).update({
        'name': asset.name,
        'tags': asset.tags,
        'pixelData': asset.pixelData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update asset: $e');
    }
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    try {
      await _firestore.collection('assets').doc(assetId).delete();
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
        'createdAt': FieldValue.serverTimestamp(),
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
        'createdAt': FieldValue.serverTimestamp(),
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
    return AssetModel(
      id: id,
      name: data['name'] ?? 'Unnamed Asset',
      type: data['type'] == 'animation' ? AssetType.animation : AssetType.image,
      tags: data['tags'] != null ? List<String>.from(data['tags']) : [],
      pixelData: data['pixelData'] != null
          ? List<List<int>>.from(
              (data['pixelData'] as List).map((row) => List<int>.from(row))
            )
          : null,
      isDefault: data['isDefault'] ?? false,
      createdAt: data['createdAt']?.toDate(),
    );
  }

  Future<void> _incrementDeviceConfigVersion(String deviceId) async {
    final deviceRef = _firestore.collection('devices').doc(deviceId);
    final currentData = await deviceRef.get();
    final currentVersion = currentData.data()?['configVersion'] ?? 0;
    await deviceRef.update({
      'configVersion': currentVersion + 1,
    });
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
}
