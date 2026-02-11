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

  DevicesCubit(this.firebaseRepository, this.userId)
      : super(DevicesState()) {
    loadDevices();
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
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
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
