import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/device_model.dart';
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
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
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
