import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/asset_model.dart';
import '../../../core/models/screen_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class ScreensPlaylistState {
  final List<ScreenModel> screens;
  final List<AssetModel> assets;
  final bool isLoading;
  final bool hasLoaded;
  final String? error;

  ScreensPlaylistState({
    this.screens = const [],
    this.assets = const [],
    this.isLoading = true,
    this.hasLoaded = false,
    this.error,
  });

  bool get isInitialLoading => isLoading && !hasLoaded;
  bool get isRefreshing => isLoading && hasLoaded;

  ScreensPlaylistState copyWith({
    List<ScreenModel>? screens,
    List<AssetModel>? assets,
    bool? isLoading,
    bool? hasLoaded,
    String? error,
    bool clearError = false,
  }) {
    return ScreensPlaylistState(
      screens: screens ?? this.screens,
      assets: assets ?? this.assets,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      error: clearError ? null : (error ?? this.error),
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
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final screens = await firebaseRepository.getScreens(deviceId);
      final assetIds = screens
          .expand(_assetIdsForScreen)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      List<AssetModel> assets = const [];
      String? assetError;
      try {
        assets = await firebaseRepository.getAssetsByIds(assetIds);
      } catch (e) {
        // Screen configuration should still be usable when an asset was
        // deleted or is temporarily unavailable.
        assetError = e.toString();
      }

      emit(state.copyWith(
        screens: screens,
        assets: assets,
        isLoading: false,
        hasLoaded: true,
        error: assetError,
        clearError: assetError == null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: e.toString(),
      ));
    }
  }

  static Iterable<String> _assetIdsForScreen(ScreenModel screen) sync* {
    if (!screen.supportsAssetPool) return;

    if (screen.availableAssetIds.isNotEmpty) {
      yield* screen.availableAssetIds;
    }
    if (screen.defaultAssetId != null) yield screen.defaultAssetId!;
    if (screen.assetId != null) yield screen.assetId!;
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

  /// Moves a screen using the raw indices a [SliverReorderableList] reports.
  ///
  /// The list reports [newIndex] against the list *before* the item is lifted
  /// out, so a downward move overshoots by one and has to be corrected.
  Future<void> moveScreen(int oldIndex, int newIndex) async {
    final screens = List<ScreenModel>.from(state.screens);
    if (oldIndex < 0 || oldIndex >= screens.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= screens.length || newIndex == oldIndex) {
      return;
    }

    screens.insert(newIndex, screens.removeAt(oldIndex));
    await reorderScreens(screens);
  }

  Future<void> reorderScreens(List<ScreenModel> reorderedScreens) async {
    // Emit first: the card has already animated into its new slot, so waiting
    // for Firestore would snap it back for the length of the round trip.
    final previousScreens = state.screens;
    emit(state.copyWith(screens: reorderedScreens, clearError: true));

    try {
      final screenIds = reorderedScreens.map((s) => s.id).toList();
      await firebaseRepository.reorderScreens(deviceId, screenIds);
    } catch (e) {
      emit(state.copyWith(screens: previousScreens, error: e.toString()));
    }
  }
}
