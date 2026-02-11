import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/asset_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class AssetsState {
  final List<AssetModel> myAssets;
  final List<AssetModel> defaultAssets;
  final bool isLoading;
  final String? error;

  AssetsState({
    this.myAssets = const [],
    this.defaultAssets = const [],
    this.isLoading = false,
    this.error,
  });

  AssetsState copyWith({
    List<AssetModel>? myAssets,
    List<AssetModel>? defaultAssets,
    bool? isLoading,
    String? error,
  }) {
    return AssetsState(
      myAssets: myAssets ?? this.myAssets,
      defaultAssets: defaultAssets ?? this.defaultAssets,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
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
    emit(state.copyWith(isLoading: true));
    try {
      final myAssets = await firebaseRepository.getUserAssets(userId);
      final defaultAssets = await firebaseRepository.getDefaultAssets();
      emit(state.copyWith(
        myAssets: myAssets,
        defaultAssets: defaultAssets,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> deleteAsset(String assetId) async {
    try {
      await firebaseRepository.deleteAsset(assetId);
      await loadAssets();
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
