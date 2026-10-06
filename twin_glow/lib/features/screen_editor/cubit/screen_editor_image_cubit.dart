import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/screen_model.dart';
import '../../../core/models/asset_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class ScreenEditorImageState {
  final ScreenModel screen;

  /// Asset previewed in the editor. Not persisted - the device starts from
  /// [defaultAssetId].
  final String? selectedAssetId;

  /// Ordered pool the device cycles through with the action button.
  final List<String> poolAssetIds;
  final String? defaultAssetId;

  final bool isShared;

  /// The user's whole asset library, used to populate the picker. Unrelated to
  /// [poolAssetIds], which is this screen's own selection.
  final List<AssetModel> availableAssets;
  final bool isLoading;
  final String? error;

  ScreenEditorImageState({
    required this.screen,
    this.selectedAssetId,
    this.poolAssetIds = const [],
    this.defaultAssetId,
    this.isShared = false,
    this.availableAssets = const [],
    this.isLoading = false,
    this.error,
  });

  ScreenEditorImageState copyWith({
    ScreenModel? screen,
    String? selectedAssetId,
    List<String>? poolAssetIds,
    String? defaultAssetId,
    bool? isShared,
    List<AssetModel>? availableAssets,
    bool? isLoading,
    String? error,
    bool clearDefaultAssetId = false,
    bool clearError = false,
  }) {
    return ScreenEditorImageState(
      screen: screen ?? this.screen,
      selectedAssetId: selectedAssetId ?? this.selectedAssetId,
      poolAssetIds: poolAssetIds ?? this.poolAssetIds,
      defaultAssetId: clearDefaultAssetId
          ? null
          : (defaultAssetId ?? this.defaultAssetId),
      isShared: isShared ?? this.isShared,
      availableAssets: availableAssets ?? this.availableAssets,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ScreenEditorImageCubit extends Cubit<ScreenEditorImageState> {
  final FirebaseRepository firebaseRepository;
  final String deviceId;
  final String userId;
  final bool isNewScreen;

  ScreenEditorImageCubit(
    this.firebaseRepository,
    this.deviceId,
    ScreenModel screen,
    List<AssetModel> availableAssets, {
    this.userId = '',
  }) : isNewScreen =
           screen.assetId == null &&
           screen.availableAssetIds.isEmpty &&
           !screen.isShared,
       super(
         ScreenEditorImageState(
           screen: screen,
           // A screen saved before the pool existed carries a single assetId;
           // treat it as a one-image pool so nothing is lost on the next save.
           poolAssetIds: _initialPool(screen),
           defaultAssetId: screen.defaultAssetId ?? screen.assetId,
           selectedAssetId: screen.defaultAssetId ?? screen.assetId,
           isShared: screen.isShared,
           availableAssets: availableAssets,
         ),
       ) {
    reloadPoolAssets();
  }

  Future<void> reloadPoolAssets() async {
    try {
      final assets = await firebaseRepository.getAssetsByIds(
        state.poolAssetIds,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            availableAssets: {
              for (final a in [...state.availableAssets, ...assets]) a.id: a,
            }.values.toList(),
          ),
        );
      }
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  static List<String> _initialPool(ScreenModel screen) {
    if (screen.availableAssetIds.isNotEmpty) {
      return List<String>.from(screen.availableAssetIds);
    }
    return screen.assetId != null ? [screen.assetId!] : const [];
  }

  /// Preview an asset without changing the pool.
  void selectAsset(String assetId) {
    emit(state.copyWith(selectedAssetId: assetId));
  }

  /// Add or remove an asset from the pool the device cycles through.
  void toggleAssetInPool(String assetId) {
    final pool = List<String>.from(state.poolAssetIds);

    if (pool.contains(assetId)) {
      pool.remove(assetId);
      // Removing the default promotes the next member so the screen always has
      // something to show first.
      if (state.defaultAssetId == assetId) {
        emit(
          state.copyWith(
            poolAssetIds: pool,
            defaultAssetId: pool.isNotEmpty ? pool.first : null,
            clearDefaultAssetId: pool.isEmpty,
            selectedAssetId: pool.isNotEmpty ? pool.first : null,
          ),
        );
        return;
      }
      emit(state.copyWith(poolAssetIds: pool, selectedAssetId: assetId));
      return;
    }

    pool.add(assetId);
    emit(
      state.copyWith(
        poolAssetIds: pool,
        // First asset added becomes the default.
        defaultAssetId: state.defaultAssetId ?? assetId,
        selectedAssetId: assetId,
      ),
    );
  }

  /// Mark which asset the screen shows first. Adds it to the pool if needed.
  void setDefaultAsset(String assetId) {
    final pool = List<String>.from(state.poolAssetIds);
    if (!pool.contains(assetId)) pool.add(assetId);
    emit(
      state.copyWith(
        poolAssetIds: pool,
        defaultAssetId: assetId,
        selectedAssetId: assetId,
      ),
    );
  }

  void renameScreen(String name) {
    emit(state.copyWith(screen: state.screen.copyWith(name: name)));
  }

  void toggleSharing() {
    emit(state.copyWith(isShared: !state.isShared));
  }

  Future<bool> save() async {
    if (state.isLoading) return false;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final pool = state.poolAssetIds;
      final defaultAssetId =
          state.defaultAssetId ?? (pool.isNotEmpty ? pool.first : null);

      // Built directly rather than via copyWith so an emptied pool can clear
      // defaultAssetId instead of retaining the previous value.
      final updatedScreen = ScreenModel(
        id: state.screen.id,
        type: state.screen.type,
        name:
            state.screen.name ??
            (state.screen.type == ScreenType.animation
                ? 'Animation Screen'
                : 'Image Screen'),
        enabled: state.screen.enabled,
        isShared: state.isShared,
        previewData: state.screen.previewData,
        // Legacy single-image field kept in sync for the device's fallback path.
        assetId: defaultAssetId,
        config: state.screen.config,
        defaultAssetId: defaultAssetId,
        availableAssetIds: pool,
        allowManualSwitch: state.screen.allowManualSwitch,
        sharedScreenId: state.screen.sharedScreenId,
        sharedVersion: state.screen.sharedVersion,
      );

      if (isNewScreen) {
        await firebaseRepository.createScreen(deviceId, updatedScreen);
      } else {
        await firebaseRepository.updateScreen(
          deviceId,
          state.screen.id,
          updatedScreen,
        );
      }

      emit(state.copyWith(isLoading: false, screen: updatedScreen));
      return true;
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
      return false;
    }
  }
}
