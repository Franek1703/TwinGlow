import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/screen_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class ScreensPlaylistState {
  final List<ScreenModel> screens;
  final bool isLoading;
  final String? error;

  ScreensPlaylistState({
    this.screens = const [],
    this.isLoading = false,
    this.error,
  });

  ScreensPlaylistState copyWith({
    List<ScreenModel>? screens,
    bool? isLoading,
    String? error,
  }) {
    return ScreensPlaylistState(
      screens: screens ?? this.screens,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ScreensPlaylistCubit extends Cubit<ScreensPlaylistState> {
  final FirebaseRepository firebaseRepository;
  final String deviceId;

  ScreensPlaylistCubit(this.firebaseRepository, this.deviceId)
      : super(ScreensPlaylistState()) {
    loadScreens();
  }

  Future<void> loadScreens() async {
    emit(state.copyWith(isLoading: true));
    try {
      final screens = await firebaseRepository.getScreens(deviceId);
      emit(state.copyWith(screens: screens, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> toggleScreen(String screenId) async {
    try {
      final screens = List<ScreenModel>.from(state.screens);
      final index = screens.indexWhere((s) => s.id == screenId);
      if (index != -1) {
        final screen = screens[index];
        final updated = screen.copyWith(enabled: !screen.enabled);
        await firebaseRepository.updateScreen(deviceId, screenId, updated);
        screens[index] = updated;
        emit(state.copyWith(screens: screens));
      }
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> reorderScreens(List<ScreenModel> reorderedScreens) async {
    try {
      final screenIds = reorderedScreens.map((s) => s.id).toList();
      await firebaseRepository.reorderScreens(deviceId, screenIds);
      emit(state.copyWith(screens: reorderedScreens));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
