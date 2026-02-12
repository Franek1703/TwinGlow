import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/screen_model.dart';
import '../../../core/models/asset_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class ScreenEditorImageState {
  final ScreenModel screen;
  final String? selectedAssetId;
  final bool isShared;
  final List<AssetModel> availableAssets;
  final bool isLoading;
  final String? error;

  ScreenEditorImageState({
    required this.screen,
    this.selectedAssetId,
    this.isShared = false,
    this.availableAssets = const [],
    this.isLoading = false,
    this.error,
  });

  ScreenEditorImageState copyWith({
    ScreenModel? screen,
    String? selectedAssetId,
    bool? isShared,
    List<AssetModel>? availableAssets,
    bool? isLoading,
    String? error,
  }) {
    return ScreenEditorImageState(
      screen: screen ?? this.screen,
      selectedAssetId: selectedAssetId ?? this.selectedAssetId,
      isShared: isShared ?? this.isShared,
      availableAssets: availableAssets ?? this.availableAssets,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ScreenEditorImageCubit extends Cubit<ScreenEditorImageState> {
  final FirebaseRepository firebaseRepository;
  final String deviceId;
  final bool isNewScreen;

  ScreenEditorImageCubit(this.firebaseRepository, this.deviceId, ScreenModel screen, List<AssetModel> availableAssets)
      : isNewScreen = screen.assetId == null && !screen.isShared,
        super(ScreenEditorImageState(
          screen: screen,
          selectedAssetId: screen.assetId,
          isShared: screen.isShared,
          availableAssets: availableAssets,
        ));

  void selectAsset(String assetId) {
    emit(state.copyWith(selectedAssetId: assetId));
  }

  void toggleSharing() {
    emit(state.copyWith(isShared: !state.isShared));
  }

  Future<void> save() async {
    emit(state.copyWith(isLoading: true));
    try {
      final updatedScreen = state.screen.copyWith(
        assetId: state.selectedAssetId,
        isShared: state.isShared,
        name: 'Image Screen',
      );

      if (isNewScreen) {
        await firebaseRepository.createScreen(deviceId, updatedScreen);
      } else {
        await firebaseRepository.updateScreen(deviceId, state.screen.id, updatedScreen);
      }

      emit(state.copyWith(isLoading: false, screen: updatedScreen));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
