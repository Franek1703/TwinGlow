import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/device_model.dart';
import '../../../core/utils/device_presence.dart';
import '../../../core/utils/device_timezone.dart';
import '../../../services/firebase/firebase_repository.dart';

class DevicesState {
  final List<DeviceModel> devices;
  final DeviceModel? activeDevice;
  final bool isLoading;
  final bool hasLoaded;
  final String? error;

  DevicesState({
    this.devices = const [],
    this.activeDevice,
    this.isLoading = true,
    this.hasLoaded = false,
    this.error,
  });

  bool get isInitialLoading => isLoading && !hasLoaded;
  bool get isRefreshing => isLoading && hasLoaded;

  DevicesState copyWith({
    List<DeviceModel>? devices,
    DeviceModel? activeDevice,
    bool? isLoading,
    bool? hasLoaded,
    String? error,
    bool clearActiveDevice = false,
    bool clearError = false,
  }) {
    return DevicesState(
      devices: devices ?? this.devices,
      activeDevice:
          clearActiveDevice ? null : (activeDevice ?? this.activeDevice),
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DevicesCubit extends Cubit<DevicesState> {
  final FirebaseRepository firebaseRepository;
  final String userId;

  /// How often the last presence write is re-judged against the clock.
  /// Only overridden by tests, which cannot wait out the real interval.
  final Duration presenceRecheckInterval;

  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;
  Timer? _presenceRecheckTimer;
  String? _presenceDeviceId;
  Map<String, dynamic>? _lastPresence;

  DevicesCubit(
    this.firebaseRepository,
    this.userId, {
    this.presenceRecheckInterval = kPresenceRecheckInterval,
  }) : super(DevicesState()) {
    loadDevices();
  }

  @override
  Future<void> close() {
    _presenceRecheckTimer?.cancel();
    _presenceSubscription?.cancel();
    return super.close();
  }

  Future<void> loadDevices() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final devices = await firebaseRepository.getDevices(userId);
      final activeDevice = devices.isNotEmpty ? devices.first : null;
      
      emit(state.copyWith(
        devices: devices,
        activeDevice: activeDevice,
        isLoading: false,
        hasLoaded: true,
        clearActiveDevice: activeDevice == null,
        clearError: true,
      ));

      // Subscribe to presence updates for active device
      if (activeDevice != null) {
        _subscribeToPresence(activeDevice.id);
      }

      // Not awaited: the device list should not wait on a platform channel.
      unawaited(_backfillTimeZones(devices));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: e.toString(),
      ));
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
    _presenceRecheckTimer?.cancel();
    _presenceDeviceId = deviceId;
    _lastPresence = null;

    _presenceSubscription = firebaseRepository
        .watchDevicePresence(deviceId)
        .listen((presenceData) {
      _lastPresence = presenceData;
      _applyPresence();
    });

    // The device stops writing when it is unplugged, so no further stream event
    // ever arrives to say it left. Re-judging the value we already hold is what
    // turns a silent device offline.
    _presenceRecheckTimer =
        Timer.periodic(presenceRecheckInterval, (_) => _applyPresence());
  }

  /// Applies the last presence write to state, aged against the current time.
  ///
  /// Emits only when the answer actually changes: this runs every
  /// [presenceRecheckInterval] and should not rebuild the tree for nothing.
  void _applyPresence() {
    final deviceId = _presenceDeviceId;
    if (deviceId == null || isClosed) return;

    final isOnline = isPresenceOnline(_lastPresence);
    final known = state.devices
        .where((device) => device.id == deviceId)
        .map((device) => device.isOnline);
    final activeMatches = state.activeDevice?.id != deviceId ||
        state.activeDevice!.isOnline == isOnline;
    if (known.every((value) => value == isOnline) && activeMatches) return;

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
