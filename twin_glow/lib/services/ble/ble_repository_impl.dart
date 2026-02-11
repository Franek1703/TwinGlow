import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_repository.dart';

// License for flutter_blue_plus
// For development: use License.free
// For production: use License.paid('your-license-key')
const _bleLicense = License.free;

// TwinGlow BLE Service and Characteristic UUIDs
// These should match the ESP32 device implementation
const String twinGlowServiceUUID = '0000ff00-0000-1000-8000-00805f9b34fb';
const String ssidCharacteristicUUID = '0000ff01-0000-1000-8000-00805f9b34fb';
const String passwordCharacteristicUUID = '0000ff02-0000-1000-8000-00805f9b34fb';
const String userIdCharacteristicUUID = '0000ff03-0000-1000-8000-00805f9b34fb';

class BleRepositoryImpl implements BLERepository {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ssidCharacteristic;
  BluetoothCharacteristic? _passwordCharacteristic;
  BluetoothCharacteristic? _userIdCharacteristic;

  @override
  Future<bool> requestPermissions() async {
    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth is not supported on this device');
      }

      // Request Bluetooth adapter state
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        // Try to turn on Bluetooth (Android only)
        await FlutterBluePlus.turnOn();
        // Wait a bit for Bluetooth to turn on
        await Future.delayed(const Duration(seconds: 2));
        state = await FlutterBluePlus.adapterState.first;
        if (state != BluetoothAdapterState.on) {
          throw Exception('Bluetooth is not enabled. Please enable Bluetooth in settings.');
        }
      }

      return true;
    } catch (e) {
      throw Exception('Failed to request Bluetooth permissions: $e');
    }
  }

  @override
  Future<List<BLEDevice>> scanForDevices() async {
    try {
      await requestPermissions();

      final List<BLEDevice> devices = [];
      final serviceUuid = Guid(twinGlowServiceUUID);

      // Start scanning with timeout
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          // Check if device advertises TwinGlow service or has a name
          if (result.advertisementData.serviceUuids.contains(serviceUuid) ||
              result.device.platformName.isNotEmpty) {
            // Avoid duplicates
            if (!devices.any((d) => d.id == result.device.remoteId.toString())) {
              devices.add(BLEDevice(
                id: result.device.remoteId.toString(),
                name: result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : 'TwinGlow Device',
                rssi: result.rssi,
              ));
            }
          }
        }
      });

      // Start scan
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withServices: [serviceUuid],
      );

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();

      return devices;
    } catch (e) {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      throw Exception('Failed to scan for devices: $e');
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    try {
      // Find device by ID from connected devices
      final devices = await FlutterBluePlus.connectedDevices;
      BluetoothDevice? device;

      for (var d in devices) {
        if (d.remoteId.toString() == deviceId) {
          device = d;
          break;
        }
      }

      if (device == null) {
        // Try to find in scan results
        final scanResults = await FlutterBluePlus.scanResults.first;
        for (var result in scanResults) {
          if (result.device.remoteId.toString() == deviceId) {
            device = result.device;
            break;
          }
        }
      }

      if (device == null) {
        throw Exception('Device not found: $deviceId');
      }

      // Connect to device
      // flutter_blue_plus v2.x requires a License parameter
      // License.free() for development, License.paid(licenseKey) for production
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
        license: _bleLicense, // Use License.paid('your-key') for production
      );

      _connectedDevice = device;

      // Discover services
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == Guid(twinGlowServiceUUID),
        orElse: () => throw Exception('TwinGlow service not found'),
      );

      // Find characteristics
      _ssidCharacteristic = service.characteristics.firstWhere(
        (c) => c.uuid == Guid(ssidCharacteristicUUID),
        orElse: () => throw Exception('SSID characteristic not found'),
      );

      _passwordCharacteristic = service.characteristics.firstWhere(
        (c) => c.uuid == Guid(passwordCharacteristicUUID),
        orElse: () => throw Exception('Password characteristic not found'),
      );

      _userIdCharacteristic = service.characteristics.firstWhere(
        (c) => c.uuid == Guid(userIdCharacteristicUUID),
        orElse: () => throw Exception('User ID characteristic not found'),
      );
    } catch (e) {
      await disconnect();
      throw Exception('Failed to connect to device: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
        _ssidCharacteristic = null;
        _passwordCharacteristic = null;
        _userIdCharacteristic = null;
      }
    } catch (e) {
      // Ignore disconnect errors
    }
  }

  @override
  Future<void> provisionDevice({
    required String deviceId,
    required String ssid,
    required String password,
    required String userId,
  }) async {
    try {
      // Connect if not already connected
      if (_connectedDevice == null || 
          _connectedDevice!.remoteId.toString() != deviceId) {
        await connect(deviceId);
      }

      if (_ssidCharacteristic == null ||
          _passwordCharacteristic == null ||
          _userIdCharacteristic == null) {
        throw Exception('Device characteristics not available');
      }

      // Write provisioning data
      await _ssidCharacteristic!.write(ssid.codeUnits, withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 200));

      await _passwordCharacteristic!.write(password.codeUnits, withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 200));

      await _userIdCharacteristic!.write(userId.codeUnits, withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 500));

      // Disconnect after provisioning
      await disconnect();
    } catch (e) {
      await disconnect();
      throw Exception('Failed to provision device: $e');
    }
  }

  void dispose() {
    _scanSubscription?.cancel();
    disconnect();
  }
}
