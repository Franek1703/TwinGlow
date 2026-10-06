import '../../core/models/device_model.dart';
import '../../core/models/screen_model.dart';
import '../../core/models/asset_model.dart';
import '../../core/models/user_model.dart';
import '../../core/models/pairing_model.dart';
import '../../core/models/shared_screen_model.dart';

/// Interface for Firebase operations
/// TODO: Implement real Firebase integration
abstract class FirebaseRepository {
  // Auth
  Future<UserModel?> signIn(String email, String password);
  Future<UserModel?> signUp(String email, String password);
  Future<void> signOut();
  Future<UserModel?> getCurrentUser();

  // Devices
  Future<List<DeviceModel>> getDevices(String userId);
  Future<DeviceModel> createDevice(String userId, DeviceModel device);
  Future<void> updateDevice(String deviceId, DeviceModel device);
  Future<void> deleteDevice(String deviceId);

  // Screens
  Future<List<ScreenModel>> getScreens(String deviceId);
  Future<ScreenModel> createScreen(String deviceId, ScreenModel screen);
  Future<void> updateScreen(
    String deviceId,
    String screenId,
    ScreenModel screen,
  );
  Future<void> deleteScreen(String deviceId, String screenId);
  Future<void> reorderScreens(String deviceId, List<String> screenIds);
  Future<void> setScreenShared(
    String deviceId,
    String screenId,
    String? pairId,
    bool isShared,
  );

  // Assets
  Future<List<AssetModel>> getAssetsByIds(List<String> assetIds);
  Future<List<AssetModel>> getUserAssets(String userId);
  Future<List<AssetModel>> getDefaultAssets();
  Future<AssetModel> createAsset(String userId, AssetModel asset);
  Future<void> updateAsset(String assetId, AssetModel asset);
  Future<void> deleteAsset(String assetId);

  // Pairing
  Future<PairingModel> getPairing(String userId);
  Stream<PairingModel> watchPairing(String userId);
  Stream<List<PairingInvite>> watchPairingInvites(
    String userId, {
    required bool incoming,
  });
  Future<List<DeviceModel>> getPairableDevices(String userId);
  Stream<Map<String, dynamic>> watchPairingAcknowledgment(
    String pairId,
    String receiverDeviceId,
  );
  Future<void> sendPairingInvite(
    String userId,
    String targetEmail,
    String deviceId,
  );
  Future<void> acceptPairingInvite(
    String userId,
    String inviteId,
    String deviceId,
  );
  Future<void> resolvePairingInvite(
    String userId,
    String inviteId,
    String status,
  );
  Future<void> unpair(String userId);
  Future<void> syncSharedScreens(String userId);
  Stream<List<SharedScreenModel>> watchSharedScreens(
    String pairId,
    String ownerUid,
  );

  // Realtime Database (RTDB) methods
  Stream<Map<String, dynamic>> watchDevicePresence(String deviceId);
  Stream<Map<String, dynamic>> watchDeviceTelemetry(String deviceId);
  Future<void> sendCommand(
    String deviceId,
    String type,
    Map<String, dynamic> payload,
  );
}
