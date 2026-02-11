import 'firebase_repository.dart';
import '../../core/models/device_model.dart';
import '../../core/models/screen_model.dart';
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
      ),
      ScreenModel(
        id: 'screen3',
        type: ScreenType.animation,
        name: 'Pulse Animation',
        enabled: true,
        isShared: true,
        previewData: _generatePulsePreview(),
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
        isDefault: false,
      ),
      AssetModel(
        id: 'asset2',
        name: 'Mountain',
        type: AssetType.image,
        tags: ['nature', 'landscape'],
        isDefault: false,
      ),
      AssetModel(
        id: 'asset3',
        name: 'Pulse',
        type: AssetType.animation,
        tags: ['effect'],
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
        isDefault: true,
      ),
      AssetModel(
        id: 'default2',
        name: 'Smile',
        type: AssetType.image,
        tags: ['emoji', 'happy'],
        isDefault: true,
      ),
      AssetModel(
        id: 'default3',
        name: 'Wave',
        type: AssetType.animation,
        tags: ['effect', 'water'],
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
}
