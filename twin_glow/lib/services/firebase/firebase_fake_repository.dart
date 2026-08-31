import 'firebase_repository.dart';
import '../../core/models/device_model.dart';
import '../../core/models/screen_model.dart';
import '../../core/models/screen_asset_references.dart';
import '../../core/models/asset_model.dart';
import '../../core/models/user_model.dart';
import '../../core/models/pairing_model.dart';

/// Fake implementation of FirebaseRepository for development
class FirebaseFakeRepository implements FirebaseRepository {
  // Mock data storage
  UserModel? _currentUser;
  final List<DeviceModel> _devices = [];
  final Map<String, List<ScreenModel>> _screens = {};
  final List<AssetModel> _userAssets = [];
  final List<AssetModel> _defaultAssets = [];
  PairingModel? _pairing;

  FirebaseFakeRepository() {
    _initializeMockData();
  }

  void _initializeMockData() {
    // Mock user
    _currentUser = UserModel(
      id: 'user1',
      email: 'john@example.com',
      displayName: 'John Doe',
    );

    // Mock device
    final device = DeviceModel(
      id: 'device1',
      name: 'My TwinGlow',
      isOnline: true,
      hasSensor: true,
      userId: 'user1',
      timezone: 'Europe/Warsaw',
      tzPosix: 'CET-1CEST,M3.5.0,M10.5.0/3',
      brightness: kDefaultBrightness,
      sleepMode: const SleepSchedule(),
    );
    _devices.add(device);

    // Mock screens
    _screens['device1'] = [
      ScreenModel(
        id: 'screen1',
        type: ScreenType.clock,
        name: 'Digital Clock',
        enabled: true,
        isShared: false,
      ),
      ScreenModel(
        id: 'screen2',
        type: ScreenType.image,
        name: 'Heart Icon',
        enabled: true,
        isShared: true,
        previewData: _generateHeartPreview(),
        assetId: 'asset1',
        defaultAssetId: 'asset1',
        availableAssetIds: const ['asset1', 'asset2'],
      ),
      ScreenModel(
        id: 'screen3',
        type: ScreenType.animation,
        name: 'Pulse Animation',
        enabled: true,
        isShared: true,
        previewData: _generatePulsePreview(),
        assetId: 'asset3',
        defaultAssetId: 'asset3',
        availableAssetIds: const ['asset3', 'default3'],
      ),
      ScreenModel(
        id: 'screen4',
        type: ScreenType.sensor,
        name: 'Temperature',
        enabled: false,
        isShared: false,
      ),
    ];

    // Mock user assets
    _userAssets.addAll([
      AssetModel(
        id: 'asset1',
        name: 'Sunset',
        type: AssetType.image,
        tags: ['nature', 'custom'],
        pixelData: _generateHeartPreview(),
        isDefault: false,
      ),
      AssetModel(
        id: 'asset2',
        name: 'Mountain',
        type: AssetType.image,
        tags: ['nature', 'landscape'],
        pixelData: _generatePulsePreview(),
        isDefault: false,
      ),
      AssetModel(
        id: 'asset3',
        name: 'Pulse',
        type: AssetType.animation,
        tags: ['effect'],
        pixelData: _generatePulsePreview(),
        isDefault: false,
      ),
    ]);

    // Mock default assets
    _defaultAssets.addAll([
      AssetModel(
        id: 'default1',
        name: 'Heart',
        type: AssetType.image,
        tags: ['emoji', 'love'],
        pixelData: _generateHeartPreview(),
        isDefault: true,
      ),
      AssetModel(
        id: 'default2',
        name: 'Smile',
        type: AssetType.image,
        tags: ['emoji', 'happy'],
        pixelData: _generatePulsePreview(),
        isDefault: true,
      ),
      AssetModel(
        id: 'default3',
        name: 'Wave',
        type: AssetType.animation,
        tags: ['effect', 'water'],
        pixelData: _generateHeartPreview(),
        isDefault: true,
      ),
    ]);

    // Mock pairing
    _pairing = PairingModel(
      pairedUserId: 'user2',
      pairedUserName: '@sarah_smith',
      sharedScreensCount: 2,
    );
  }

  List<List<int>> _generateHeartPreview() {
    final grid = List.generate(16, (_) => List.filled(16, 0));
    const magenta = 0xff006e;
    final heartPattern = [
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0],
      [0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0],
      [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
      [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
      [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
      [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
      [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
      [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ];

    for (var r = 0; r < 16; r++) {
      for (var c = 0; c < 16; c++) {
        if (r < heartPattern.length &&
            c < heartPattern[r].length &&
            heartPattern[r][c] == 1) {
          grid[r][c] = magenta;
        }
      }
    }

    return grid;
  }

  List<List<int>> _generatePulsePreview() {
    final grid = List.generate(16, (_) => List.filled(16, 0));
    const cyan = 0x00d9ff;

    for (var r = 0; r < 16; r++) {
      for (var c = 0; c < 16; c++) {
        final dx = c - 8;
        final dy = r - 8;
        final dist = (dx * dx + dy * dy).toDouble();
        if (dist > 16 && dist < 36) {
          grid[r][c] = cyan;
        }
      }
    }

    return grid;
  }

  // Auth
  @override
  Future<UserModel?> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = UserModel(
      id: 'user1',
      email: email,
      displayName: 'John Doe',
    );
    return _currentUser;
  }

  @override
  Future<UserModel?> signUp(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = UserModel(
      id: 'user1',
      email: email,
      displayName: email.split('@')[0],
    );
    return _currentUser;
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _currentUser = null;
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _currentUser;
  }

  // Devices
  @override
  Future<List<DeviceModel>> getDevices(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _devices.where((d) => d.userId == userId).toList();
  }

  @override
  Future<DeviceModel> createDevice(String userId, DeviceModel device) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _devices.add(device);
    return device;
  }

  @override
  Future<void> updateDevice(String deviceId, DeviceModel device) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index != -1) {
      _devices[index] = device;
    }
  }

  @override
  Future<void> deleteDevice(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _devices.removeWhere((d) => d.id == deviceId);
  }

  // Screens
  @override
  Future<List<ScreenModel>> getScreens(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _screens[deviceId] ?? [];
  }

  @override
  Future<ScreenModel> createScreen(String deviceId, ScreenModel screen) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _screens.putIfAbsent(deviceId, () => []).add(screen);
    return screen;
  }

  @override
  Future<void> updateScreen(
      String deviceId, String screenId, ScreenModel screen) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final screens = _screens[deviceId];
    if (screens != null) {
      final index = screens.indexWhere((s) => s.id == screenId);
      if (index != -1) {
        screens[index] = screen;
      }
    }
  }

  @override
  Future<void> deleteScreen(String deviceId, String screenId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final screens = _screens[deviceId];
    if (screens != null) {
      screens.removeWhere((s) => s.id == screenId);
    }
  }

  @override
  Future<void> setScreenShared(
    String deviceId,
    String screenId,
    String? pairId,
    bool isShared,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final screens = _screens[deviceId];
    if (screens == null) return;
    final index = screens.indexWhere((s) => s.id == screenId);
    if (index != -1) {
      screens[index] = screens[index].copyWith(isShared: isShared);
    }
  }

  @override
  Future<void> reorderScreens(String deviceId, List<String> screenIds) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final screens = _screens[deviceId];
    if (screens != null) {
      final ordered = screenIds
          .map((id) => screens.firstWhere((s) => s.id == id))
          .toList();
      _screens[deviceId] = ordered;
    }
  }

  // Assets
  @override
  Future<List<AssetModel>> getAssetsByIds(List<String> assetIds) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final ids = assetIds.toSet();
    return [..._userAssets, ..._defaultAssets]
        .where((asset) => ids.contains(asset.id))
        .toList();
  }

  @override
  Future<List<AssetModel>> getUserAssets(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _userAssets;
  }

  @override
  Future<List<AssetModel>> getDefaultAssets() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _defaultAssets;
  }

  @override
  Future<AssetModel> createAsset(String userId, AssetModel asset) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _userAssets.add(asset);
    return asset;
  }

  @override
  Future<void> updateAsset(String assetId, AssetModel asset) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _userAssets.indexWhere((a) => a.id == assetId);
    if (index != -1) {
      _userAssets[index] = asset;
    }
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _userAssets.removeWhere((a) => a.id == assetId);

    for (final screens in _screens.values) {
      for (var index = 0; index < screens.length; index++) {
        final screen = screens[index];
        final references = ScreenAssetReferences(
          assetId: screen.assetId,
          defaultAssetId: screen.defaultAssetId,
          availableAssetIds: screen.availableAssetIds,
        );
        if (!references.contains(assetId)) continue;

        final cleanedReferences = references.without(assetId);
        screens[index] = ScreenModel(
          id: screen.id,
          type: screen.type,
          name: screen.name,
          enabled: screen.enabled,
          isShared: screen.isShared,
          previewData: screen.previewData,
          assetId: cleanedReferences.assetId,
          config: screen.config,
          defaultAssetId: cleanedReferences.defaultAssetId,
          availableAssetIds: cleanedReferences.availableAssetIds,
          allowManualSwitch: screen.allowManualSwitch,
        );
      }
    }
  }

  // Pairing
  @override
  Future<PairingModel> getPairing(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _pairing ?? PairingModel();
  }

  @override
  Future<void> sendPairingInvite(String userId, String targetEmail) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Mock implementation
  }

  @override
  Future<void> acceptPairingInvite(String userId, String inviteId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _pairing = PairingModel(
      pairedUserId: 'user2',
      pairedUserName: '@sarah_smith',
      sharedScreensCount: 2,
    );
  }

  @override
  Future<void> unpair(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _pairing = PairingModel();
  }

  // RTDB methods (mock implementations)
  @override
  Stream<Map<String, dynamic>> watchDevicePresence(String deviceId) {
    // Return a stream that emits mock presence data. The key is lastSeenMs,
    // the one the firmware writes and isPresenceOnline() ages.
    return Stream.value({
      'online': true,
      'lastSeenMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Stream<Map<String, dynamic>> watchDeviceTelemetry(String deviceId) {
    // Return a stream that emits mock telemetry data
    return Stream.value({
      'temperature': 22.5,
      'humidity': 45.0,
      'pressure': 1013.25,
    });
  }

  @override
  Future<void> sendCommand(String deviceId, String type, Map<String, dynamic> payload) async {
    // Mock command sending
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
