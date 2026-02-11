/// Interface for BLE operations
/// TODO: Implement real BLE integration
abstract class BLERepository {
  Future<bool> requestPermissions();
  Future<List<BLEDevice>> scanForDevices();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> provisionDevice({
    required String deviceId,
    required String ssid,
    required String password,
    required String userId,
  });
}

class BLEDevice {
  final String id;
  final String name;
  final int rssi; // Signal strength

  BLEDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
}
