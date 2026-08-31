import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/asset_model.dart';
import '../../../services/animation_import/animation_crop.dart';
import '../../../services/animation_import/animation_import_converter.dart';
import '../../../services/animation_import/animation_import_service.dart';
import '../../../services/image_import/editor_image_converter.dart';
import '../../../services/image_import/image_import_service.dart';

enum AnimationImportStatus {
  idle,
  selecting,
  decoding,
  awaitingCrop,
  converting,
  ready,
  cancelled,
  failure,
}

class AnimationImportState {
  final AnimationImportStatus status;
  final SelectedImportAnimation? selection;
  final AnimationPreviewSource? preview;
  final NormalizedCrop? crop;
  final AnimationConversionResult? conversion;
  final ImageConversionMode mode;
  final String? error;

  const AnimationImportState({
    this.status = AnimationImportStatus.idle,
    this.selection,
    this.preview,
    this.crop,
    this.conversion,
    this.mode = ImageConversionMode.photo,
    this.error,
  });

  List<AnimationFrameModel>? get frames => conversion?.framesFor(mode);

  AnimationImportState copyWith({
    AnimationImportStatus? status,
    SelectedImportAnimation? selection,
    AnimationPreviewSource? preview,
    NormalizedCrop? crop,
    AnimationConversionResult? conversion,
    ImageConversionMode? mode,
    String? error,
    bool clearError = false,
  }) {
    return AnimationImportState(
      status: status ?? this.status,
      selection: selection ?? this.selection,
      preview: preview ?? this.preview,
      crop: crop ?? this.crop,
      conversion: conversion ?? this.conversion,
      mode: mode ?? this.mode,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives selection, cropping, and conversion for animation import.
///
/// Cropping is an in-app screen rather than a plugin call, so the cubit does
/// not own it: it parks in [AnimationImportStatus.awaitingCrop] and waits for
/// the view to report the selection back through [applyCrop] or [cancelCrop].
class AnimationImportCubit extends Cubit<AnimationImportState> {
  final AnimationImportService service;

  AnimationImportCubit(this.service) : super(const AnimationImportState());

  Future<void> start(ImageImportSource source) async {
    emit(const AnimationImportState(status: AnimationImportStatus.selecting));
    try {
      final selected = await service.selectAnimation(source);
      if (selected == null) {
        emit(
          const AnimationImportState(status: AnimationImportStatus.cancelled),
        );
        return;
      }

      emit(
        AnimationImportState(
          status: AnimationImportStatus.decoding,
          selection: selected,
        ),
      );
      final preview = await service.loadPreview(selected.path);
      emit(
        AnimationImportState(
          status: AnimationImportStatus.awaitingCrop,
          selection: selected,
          preview: preview,
          crop: NormalizedCrop.centered(
            preview.sourceWidth,
            preview.sourceHeight,
          ),
        ),
      );
    } on ImageImportFailure catch (error) {
      emit(
        AnimationImportState(
          status: AnimationImportStatus.failure,
          error: error.message,
        ),
      );
    }
  }

  /// Re-opens the crop step over the animation already selected.
  void changeCrop() {
    if (state.preview == null || state.conversion == null) return;
    emit(
      state.copyWith(
        status: AnimationImportStatus.awaitingCrop,
        clearError: true,
      ),
    );
  }

  /// Backing out of the crop step. The first crop has nothing to fall back to,
  /// so it ends the import; a recrop keeps the preview already on screen.
  void cancelCrop() {
    if (state.conversion == null) {
      emit(const AnimationImportState(status: AnimationImportStatus.cancelled));
      return;
    }
    emit(state.copyWith(status: AnimationImportStatus.ready, clearError: true));
  }

  Future<void> applyCrop(NormalizedCrop crop) async {
    final selection = state.selection;
    if (selection == null) return;
    final previousConversion = state.conversion;

    emit(
      state.copyWith(
        status: AnimationImportStatus.converting,
        crop: crop,
        clearError: true,
      ),
    );
    try {
      final conversion = await service.convert(selection.path, crop);
      emit(
        state.copyWith(
          status: AnimationImportStatus.ready,
          conversion: conversion,
          mode: conversion.suggestedMode,
          clearError: true,
        ),
      );
    } on ImageImportFailure catch (error) {
      // A failed recrop must not throw away a preview that already worked.
      if (previousConversion != null) {
        emit(
          state.copyWith(
            status: AnimationImportStatus.ready,
            conversion: previousConversion,
            error: error.message,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: AnimationImportStatus.failure,
          error: error.message,
        ),
      );
    }
  }

  void setMode(ImageConversionMode mode) {
    if (state.conversion == null || state.mode == mode) return;
    emit(state.copyWith(mode: mode, clearError: true));
  }
}
