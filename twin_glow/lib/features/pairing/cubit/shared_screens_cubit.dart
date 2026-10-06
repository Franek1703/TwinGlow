import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/pairing_model.dart';
import '../../../core/models/shared_screen_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class SharedScreensState {
  final PairingModel pairing;
  final List<SharedScreenModel> screens;
  final bool isLoading;
  final String? error;
  SharedScreensState({
    PairingModel? pairing,
    this.screens = const [],
    this.isLoading = false,
    this.error,
  }) : pairing = pairing ?? PairingModel();
}

class SharedScreensCubit extends Cubit<SharedScreensState> {
  final FirebaseRepository repository;
  final String userId;
  StreamSubscription<PairingModel>? _pair;
  StreamSubscription<List<SharedScreenModel>>? _screens;
  int _generation = 0;
  String? _pairKey;

  SharedScreensCubit(this.repository, this.userId)
    : super(SharedScreensState()) {
    _pair = repository.watchPairing(userId).listen(_paired, onError: _failed);
  }

  void _paired(PairingModel pair) {
    final key =
        '${pair.pairId}/${pair.pairedUserId}/${pair.deviceId}/${pair.partnerDeviceId}';
    if (key == _pairKey || isClosed) return;
    _pairKey = key;
    final generation = ++_generation;
    _screens?.cancel();
    _screens = null;
    emit(SharedScreensState(pairing: pair, isLoading: pair.isPaired));
    if (!pair.isPaired || pair.pairId == null || pair.pairedUserId == null) {
      return;
    }
    _screens = repository
        .watchSharedScreens(pair.pairId!, pair.pairedUserId!)
        .listen(
          (screens) {
            if (!isClosed && generation == _generation) {
              emit(
                SharedScreensState(
                  pairing: pair,
                  screens: screens,
                  error: state.error,
                ),
              );
            }
          },
          onError: (Object error) {
            if (generation == _generation) _failed(error);
          },
        );
    _sync(generation);
  }

  Future<void> _sync(int generation) async {
    try {
      await repository.syncSharedScreens(userId);
    } catch (e) {
      if (generation == _generation) _failed(e);
    }
  }

  void _failed(Object error) {
    if (!isClosed) {
      emit(
        SharedScreensState(
          pairing: state.pairing,
          screens: state.screens,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> retry() async {
    try {
      final pair = await repository.getPairing(userId);
      _pairKey = null;
      _paired(pair);
    } catch (e) {
      _failed(e);
    }
  }

  @override
  Future<void> close() async {
    ++_generation;
    await _pair?.cancel();
    await _screens?.cancel();
    return super.close();
  }
}
