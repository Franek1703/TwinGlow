import 'ble_repository.dart';

/// Fake implementation of BLERepository for development
class BLEFakeRepository implements BLERepository {
  @override
  Future<bool> requestPermissions() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  @override
  Future<List<BLEDevice>> scanForDevices() async {
    await Future.delayed(const Duration(seconds: 2));
    return [
      BLEDevice(id: 'ble1', name: 'TwinGlow Device #1', rssi: -45),
      BLEDevice(id: 'ble2', name: 'TwinGlow Device #2', rssi: -67),
    ];
  }

  @override
  Future<void> connect(String deviceId) async {
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Future<void> disconnect() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> provisionDevice({
    required String deviceId,
    required String ssid,
    required String password,
    required String userId,
  }) async {
    await Future.delayed(const Duration(seconds: 2));
    // Mock provisioning
  }
}
