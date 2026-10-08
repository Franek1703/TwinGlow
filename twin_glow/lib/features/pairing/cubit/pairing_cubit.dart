import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/pairing_model.dart';
import '../../../core/models/device_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class PairingState {
  final PairingModel pairing;
  final List<PairingInvite> incoming, outgoing;
  final List<DeviceModel> devices;
  final bool isLoading, hasLoaded, isBusy;
  final String? error;
  final Map<String, dynamic> acknowledgment;
  PairingState({
    PairingModel? pairing,
    this.incoming = const [],
    this.outgoing = const [],
    this.devices = const [],
    this.isLoading = true,
    this.hasLoaded = false,
    this.isBusy = false,
    this.error,
    this.acknowledgment = const {},
  }) : pairing = pairing ?? PairingModel();
  bool get isInitialLoading => isLoading && !hasLoaded;
  bool get isRefreshing => isLoading && hasLoaded;
  PairingState copyWith({
    PairingModel? pairing,
    List<PairingInvite>? incoming,
    List<PairingInvite>? outgoing,
    List<DeviceModel>? devices,
    bool? isLoading,
    bool? hasLoaded,
    bool? isBusy,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? acknowledgment,
  }) => PairingState(
    pairing: pairing ?? this.pairing,
    incoming: incoming ?? this.incoming,
    outgoing: outgoing ?? this.outgoing,
    devices: devices ?? this.devices,
    isLoading: isLoading ?? this.isLoading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    isBusy: isBusy ?? this.isBusy,
    error: clearError ? null : (error ?? this.error),
    acknowledgment: acknowledgment ?? this.acknowledgment,
  );
}

class PairingCubit extends Cubit<PairingState> {
  final FirebaseRepository firebaseRepository;
  final String userId;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<Map<String, dynamic>>? _ack;
  PairingCubit(this.firebaseRepository, this.userId) : super(PairingState()) {
    loadPairing();
    _subscriptions.add(
      firebaseRepository.watchPairing(userId).listen(_paired, onError: _failed),
    );
    _subscriptions.add(
      firebaseRepository.watchPairingInvites(userId, incoming: true).listen((
        i,
      ) {
        if (!isClosed) emit(state.copyWith(incoming: i));
      }, onError: _failed),
    );
    _subscriptions.add(
      firebaseRepository.watchPairingInvites(userId, incoming: false).listen((
        i,
      ) {
        if (!isClosed) emit(state.copyWith(outgoing: i));
      }, onError: _failed),
    );
  }
  void _failed(Object error) {
    if (!isClosed) {
      emit(
        state.copyWith(
          error: error.toString(),
          isLoading: false,
          hasLoaded: true,
        ),
      );
    }
  }

  void _paired(PairingModel p) {
    if (isClosed) return;
    final changed = state.pairing.pairId != p.pairId;
    emit(state.copyWith(pairing: p, acknowledgment: changed ? {} : null));
    if (changed) {
      _ack?.cancel();
      _ack = null;
      if (p.pairId != null && p.partnerDeviceId != null) {
        _ack = firebaseRepository
            .watchPairingAcknowledgment(p.pairId!, p.partnerDeviceId!)
            .listen((a) {
              if (!isClosed) emit(state.copyWith(acknowledgment: a));
            }, onError: _failed);
      }
    }
  }

  Future<void> loadPairing() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final devices = await firebaseRepository.getPairableDevices(userId);
      final p = await firebaseRepository.getPairing(userId);
      if (isClosed) return;
      _paired(p);
      emit(state.copyWith(devices: devices, isLoading: false, hasLoaded: true));
    } catch (e) {
      _failed(e);
    }
  }

  Future<bool> _operate(Future<void> Function() operation) async {
    if (state.isBusy) return false;
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      await operation();
      if (isClosed) return false;
      emit(state.copyWith(isBusy: false));
      return true;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(isBusy: false, error: e.toString()));
      return false;
    }
  }

  Future<bool> sendInvite(String email, String deviceId) => _operate(
    () => firebaseRepository.sendPairingInvite(userId, email, deviceId),
  );
  Future<bool> acceptInvite(String id, String deviceId) => _operate(
    () => firebaseRepository.acceptPairingInvite(userId, id, deviceId),
  );
  Future<bool> resolveInvite(String id, String status) => _operate(
    () => firebaseRepository.resolvePairingInvite(userId, id, status),
  );
  Future<bool> unpair() => _operate(() => firebaseRepository.unpair(userId));
  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _ack?.cancel();
    return super.close();
  }
}
