import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/image_import/image_import_converter.dart';
import '../../../services/image_import/image_import_service.dart';

enum ImageImportStatus {
  idle,
  selecting,
  cropping,
  converting,
  ready,
  cancelled,
  failure,
}

class ImageImportState {
  final ImageImportStatus status;
  final SelectedImportImage? selectedImage;
  final String? croppedPath;
  final ImageConversionResult? conversion;
  final ImageConversionMode mode;
  final String? error;

  const ImageImportState({
    this.status = ImageImportStatus.idle,
    this.selectedImage,
    this.croppedPath,
    this.conversion,
    this.mode = ImageConversionMode.photo,
    this.error,
  });

  List<List<int>>? get pixelData => conversion?.dataFor(mode);

  ImageImportState copyWith({
    ImageImportStatus? status,
    SelectedImportImage? selectedImage,
    String? croppedPath,
    ImageConversionResult? conversion,
    ImageConversionMode? mode,
    String? error,
    bool clearError = false,
  }) {
    return ImageImportState(
      status: status ?? this.status,
      selectedImage: selectedImage ?? this.selectedImage,
      croppedPath: croppedPath ?? this.croppedPath,
      conversion: conversion ?? this.conversion,
      mode: mode ?? this.mode,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ImageImportCubit extends Cubit<ImageImportState> {
  final ImageImportService service;

  ImageImportCubit(this.service) : super(const ImageImportState());

  Future<void> start(ImageImportSource source) async {
    emit(const ImageImportState(status: ImageImportStatus.selecting));
    try {
      final selected = await service.selectImage(source);
      if (selected == null) {
        emit(const ImageImportState(status: ImageImportStatus.cancelled));
        return;
      }

      emit(
        ImageImportState(
          status: ImageImportStatus.cropping,
          selectedImage: selected,
        ),
      );
      final croppedPath = await service.cropToSquare(selected.path);
      if (croppedPath == null) {
        emit(const ImageImportState(status: ImageImportStatus.cancelled));
        return;
      }
      await _convert(selected, croppedPath);
    } on ImageImportFailure catch (error) {
      emit(
        ImageImportState(
          status: ImageImportStatus.failure,
          error: error.message,
        ),
      );
    }
  }

  Future<void> changeCrop() async {
    final selected = state.selectedImage;
    final previousConversion = state.conversion;
    if (selected == null || previousConversion == null) return;

    emit(state.copyWith(status: ImageImportStatus.cropping, clearError: true));
    try {
      final croppedPath = await service.cropToSquare(selected.path);
      if (croppedPath == null) {
        emit(
          state.copyWith(
            status: ImageImportStatus.ready,
            conversion: previousConversion,
            clearError: true,
          ),
        );
        return;
      }
      await _convert(selected, croppedPath);
    } on ImageImportFailure catch (error) {
      emit(
        state.copyWith(
          status: ImageImportStatus.ready,
          conversion: previousConversion,
          error: error.message,
        ),
      );
    }
  }

  void setMode(ImageConversionMode mode) {
    if (state.conversion == null || state.mode == mode) return;
    emit(state.copyWith(mode: mode, clearError: true));
  }

  Future<void> _convert(
    SelectedImportImage selected,
    String croppedPath,
  ) async {
    emit(
      state.copyWith(
        status: ImageImportStatus.converting,
        selectedImage: selected,
        croppedPath: croppedPath,
        clearError: true,
      ),
    );
    final conversion = await service.convertCroppedImage(croppedPath);
    emit(
      state.copyWith(
        status: ImageImportStatus.ready,
        conversion: conversion,
        mode: conversion.suggestedMode,
        clearError: true,
      ),
    );
  }
}
