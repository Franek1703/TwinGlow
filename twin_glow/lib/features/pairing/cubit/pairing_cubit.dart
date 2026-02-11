import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/pairing_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class PairingState {
  final PairingModel pairing;
  final bool isLoading;
  final String? error;

  PairingState({
    PairingModel? pairing,
    this.isLoading = false,
    this.error,
  }) : pairing = pairing ?? PairingModel();

  PairingState copyWith({
    PairingModel? pairing,
    bool? isLoading,
    String? error,
  }) {
    return PairingState(
      pairing: pairing ?? this.pairing,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class PairingCubit extends Cubit<PairingState> {
  final FirebaseRepository firebaseRepository;
  final String userId;

  PairingCubit(this.firebaseRepository, this.userId) : super(PairingState()) {
    loadPairing();
  }

  Future<void> loadPairing() async {
    emit(state.copyWith(isLoading: true));
    try {
      final pairing = await firebaseRepository.getPairing(userId);
      emit(state.copyWith(pairing: pairing, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> sendInvite(String targetEmail) async {
    emit(state.copyWith(isLoading: true));
    try {
      await firebaseRepository.sendPairingInvite(userId, targetEmail);
      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> acceptInvite(String inviteId) async {
    emit(state.copyWith(isLoading: true));
    try {
      await firebaseRepository.acceptPairingInvite(userId, inviteId);
      await loadPairing();
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> unpair() async {
    emit(state.copyWith(isLoading: true));
    try {
      await firebaseRepository.unpair(userId);
      await loadPairing();
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
