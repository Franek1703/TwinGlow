import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/asset_model.dart';
import '../../../core/widgets/pixel_grid_editor.dart';

class AssetEditorState {
  final AssetModel? asset;
  final List<List<int>> pixelData;
  final Color currentColor;
  final DrawingTool currentTool;
  final String name;
  final List<String> tags;
  final bool isLoading;
  final String? error;

  AssetEditorState({
    this.asset,
    List<List<int>>? pixelData,
    this.currentColor = const Color(0xFF00D9FF),
    this.currentTool = DrawingTool.pencil,
    this.name = '',
    this.tags = const [],
    this.isLoading = false,
    this.error,
  }) : pixelData = pixelData ?? _createEmptyGrid();

  static List<List<int>> _createEmptyGrid() {
    return List.generate(16, (_) => List.filled(16, 0));
  }

  AssetEditorState copyWith({
    AssetModel? asset,
    List<List<int>>? pixelData,
    Color? currentColor,
    DrawingTool? currentTool,
    String? name,
    List<String>? tags,
    bool? isLoading,
    String? error,
  }) {
    return AssetEditorState(
      asset: asset ?? this.asset,
      pixelData: pixelData ?? this.pixelData,
      currentColor: currentColor ?? this.currentColor,
      currentTool: currentTool ?? this.currentTool,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class AssetEditorCubit extends Cubit<AssetEditorState> {
  AssetEditorCubit({AssetModel? asset})
      : super(AssetEditorState(
          asset: asset,
          pixelData: asset?.pixelData ?? AssetEditorState._createEmptyGrid(),
          name: asset?.name ?? '',
          tags: asset?.tags ?? [],
        ));

  void updatePixelData(List<List<int>> data) {
    emit(state.copyWith(pixelData: data));
  }

  void setCurrentColor(Color color) {
    emit(state.copyWith(currentColor: color));
  }

  void setCurrentTool(DrawingTool tool) {
    emit(state.copyWith(currentTool: tool));
  }

  void updateName(String name) {
    emit(state.copyWith(name: name));
  }

  void addTag(String tag) {
    if (tag.isEmpty || state.tags.contains(tag)) return;
    emit(state.copyWith(tags: [...state.tags, tag]));
  }

  void removeTag(String tag) {
    emit(state.copyWith(tags: state.tags.where((t) => t != tag).toList()));
  }

  void clearGrid() {
    emit(state.copyWith(pixelData: AssetEditorState._createEmptyGrid()));
  }

  void mirrorX() {
    final newData = state.pixelData.map((row) => row.reversed.toList()).toList();
    emit(state.copyWith(pixelData: newData));
  }

  void mirrorY() {
    final newData = state.pixelData.reversed.toList();
    emit(state.copyWith(pixelData: newData));
  }

  Future<void> save() async {
    if (state.name.isEmpty) {
      emit(state.copyWith(error: 'Name is required'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      // TODO: Save to Firebase via repository
      await Future.delayed(const Duration(milliseconds: 500));
      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
