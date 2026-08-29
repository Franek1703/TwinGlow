import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/device_model.dart';
import '../../../core/utils/device_timezone.dart';
import '../../../services/firebase/firebase_repository.dart';

class DevicesState {
  final List<DeviceModel> devices;
  final DeviceModel? activeDevice;
  final bool isLoading;
  final String? error;

  DevicesState({
    this.devices = const [],
    this.activeDevice,
    this.isLoading = false,
    this.error,
  });

  DevicesState copyWith({
    List<DeviceModel>? devices,
    DeviceModel? activeDevice,
    bool? isLoading,
    String? error,
  }) {
    return DevicesState(
      devices: devices ?? this.devices,
      activeDevice: activeDevice ?? this.activeDevice,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class DevicesCubit extends Cubit<DevicesState> {
  final FirebaseRepository firebaseRepository;
  final String userId;
  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;

  DevicesCubit(this.firebaseRepository, this.userId)
      : super(DevicesState()) {
    loadDevices();
  }

  @override
  Future<void> close() {
    _presenceSubscription?.cancel();
    return super.close();
  }

  Future<void> loadDevices() async {
    emit(state.copyWith(isLoading: true));
    try {
      final devices = await firebaseRepository.getDevices(userId);
      final activeDevice = devices.isNotEmpty ? devices.first : null;
      
      emit(state.copyWith(
        devices: devices,
        activeDevice: activeDevice,
        isLoading: false,
      ));

      // Subscribe to presence updates for active device
      if (activeDevice != null) {
        _subscribeToPresence(activeDevice.id);
      }

      // Not awaited: the device list should not wait on a platform channel.
      unawaited(_backfillTimeZones(devices));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  /// Gives a device its first timezone, taken from the phone.
  ///
  /// Only fills the field when it is absent. A zone that is already set is left
  /// alone even when the phone disagrees - travelling abroad should not re-zone
  /// the clock sitting at home. After this, only the picker changes it.
  Future<void> _backfillTimeZones(List<DeviceModel> devices) async {
    final missing = devices
        .where((d) => d.tzPosix == null || d.tzPosix!.isEmpty)
        .toList();
    if (missing.isEmpty) return;

    final zone = await resolvePhoneTimeZone();
    final updated = <String, DeviceModel>{};
    for (final device in missing) {
      final withZone =
          device.copyWith(timezone: zone.iana, tzPosix: zone.posix);
      try {
        // The repository directly, not updateDevice(): that reloads the list,
        // which is what called this in the first place.
        await firebaseRepository.updateDevice(device.id, withZone);
        updated[device.id] = withZone;
      } catch (_) {
        // A device we cannot write to keeps running on the firmware default.
        // The picker is still there to set it by hand.
      }
    }
    if (updated.isEmpty || isClosed) return;

    emit(state.copyWith(
      devices: state.devices.map((d) => updated[d.id] ?? d).toList(),
      activeDevice: updated[state.activeDevice?.id] ?? state.activeDevice,
    ));
  }

  void _subscribeToPresence(String deviceId) {
    _presenceSubscription?.cancel();
    _presenceSubscription = firebaseRepository
        .watchDevicePresence(deviceId)
        .listen((presenceData) {
      final isOnline = presenceData['online'] == true;
      
      // Update device online status
      final updatedDevices = state.devices.map((device) {
        if (device.id == deviceId) {
          return device.copyWith(isOnline: isOnline);
        }
        return device;
      }).toList();

      final updatedActiveDevice = state.activeDevice?.id == deviceId
          ? state.activeDevice!.copyWith(isOnline: isOnline)
          : state.activeDevice;

      emit(state.copyWith(
        devices: updatedDevices,
        activeDevice: updatedActiveDevice,
      ));
    });
  }

  Future<void> setActiveDevice(DeviceModel device) async {
    emit(state.copyWith(activeDevice: device));
  }

  Future<void> updateDevice(DeviceModel device) async {
    try {
      await firebaseRepository.updateDevice(device.id, device);
      await loadDevices();
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
