import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/asset_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class AssetsState {
  final List<AssetModel> myAssets;
  final List<AssetModel> defaultAssets;
  final bool isLoading;
  final bool hasLoaded;
  final String? error;
  final Set<String> deletingAssetIds;

  AssetsState({
    this.myAssets = const [],
    this.defaultAssets = const [],
    this.isLoading = true,
    this.hasLoaded = false,
    this.error,
    this.deletingAssetIds = const {},
  });

  bool get isInitialLoading => isLoading && !hasLoaded;
  bool get isRefreshing => isLoading && hasLoaded;

  AssetsState copyWith({
    List<AssetModel>? myAssets,
    List<AssetModel>? defaultAssets,
    bool? isLoading,
    bool? hasLoaded,
    String? error,
    Set<String>? deletingAssetIds,
    bool clearError = false,
  }) {
    return AssetsState(
      myAssets: myAssets ?? this.myAssets,
      defaultAssets: defaultAssets ?? this.defaultAssets,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      error: clearError ? null : (error ?? this.error),
      deletingAssetIds: deletingAssetIds ?? this.deletingAssetIds,
    );
  }
}

class AssetsCubit extends Cubit<AssetsState> {
  final FirebaseRepository firebaseRepository;
  final String userId;

  AssetsCubit(this.firebaseRepository, this.userId) : super(AssetsState()) {
    loadAssets();
  }

  Future<void> loadAssets() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final myAssets = await firebaseRepository.getUserAssets(userId);
      final defaultAssets = await firebaseRepository.getDefaultAssets();
      emit(state.copyWith(
        myAssets: myAssets,
        defaultAssets: defaultAssets,
        isLoading: false,
        hasLoaded: true,
        clearError: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: e.toString(),
      ));
    }
  }

  Future<bool> deleteAsset(String assetId) async {
    emit(state.copyWith(
      deletingAssetIds: {...state.deletingAssetIds, assetId},
      clearError: true,
    ));
    try {
      await firebaseRepository.deleteAsset(assetId);
      emit(state.copyWith(
        myAssets: state.myAssets
            .where((asset) => asset.id != assetId)
            .toList(growable: false),
        deletingAssetIds: {...state.deletingAssetIds}..remove(assetId),
        clearError: true,
      ));
      return true;
    } catch (e) {
      emit(state.copyWith(
        deletingAssetIds: {...state.deletingAssetIds}..remove(assetId),
        error: e.toString(),
      ));
      return false;
    }
  }
}
