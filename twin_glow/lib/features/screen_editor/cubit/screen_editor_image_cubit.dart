import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/screen_model.dart';
import '../../../core/models/asset_model.dart';

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
  ScreenEditorImageCubit(ScreenModel screen, List<AssetModel> availableAssets)
      : super(ScreenEditorImageState(
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
      // TODO: Save to Firebase via repository
      await Future.delayed(const Duration(milliseconds: 300));
      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
