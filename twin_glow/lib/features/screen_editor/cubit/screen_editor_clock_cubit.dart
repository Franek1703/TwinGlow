import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/screen_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class ScreenEditorClockState {
  final ScreenModel screen;
  final Color digitColor;
  final Color colonColor;
  final Color backgroundColor;
  final bool showSeconds;
  final bool isLoading;
  final String? error;

  ScreenEditorClockState({
    required this.screen,
    this.digitColor = const Color(0xFF00D9FF),
    this.colonColor = const Color(0xFF00D9FF),
    this.backgroundColor = Colors.black,
    this.showSeconds = true,
    this.isLoading = false,
    this.error,
  });

  ScreenEditorClockState copyWith({
    ScreenModel? screen,
    Color? digitColor,
    Color? colonColor,
    Color? backgroundColor,
    bool? showSeconds,
    bool? isLoading,
    String? error,
  }) {
    return ScreenEditorClockState(
      screen: screen ?? this.screen,
      digitColor: digitColor ?? this.digitColor,
      colonColor: colonColor ?? this.colonColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      showSeconds: showSeconds ?? this.showSeconds,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ScreenEditorClockCubit extends Cubit<ScreenEditorClockState> {
  final FirebaseRepository firebaseRepository;
  final String deviceId;
  final bool isNewScreen;

  ScreenEditorClockCubit(
    this.firebaseRepository,
    this.deviceId,
    ScreenModel screen,
  ) : isNewScreen = screen.config == null,
      super(
        ScreenEditorClockState(
          screen: screen,
          digitColor: _getColorFromConfig(
            screen.config,
            'digitColor',
            const Color(0xFF00D9FF),
          ),
          colonColor: _getColorFromConfig(
            screen.config,
            'colonColor',
            const Color(0xFF00D9FF),
          ),
          backgroundColor: _getColorFromConfig(
            screen.config,
            'backgroundColor',
            Colors.black,
          ),
          showSeconds: screen.config?['showSeconds'] ?? true,
        ),
      );

  static Color _getColorFromConfig(
    Map<String, dynamic>? config,
    String key,
    Color defaultValue,
  ) {
    if (config == null || config[key] == null) return defaultValue;
    final value = config[key];
    if (value is int) return Color(value);
    if (value is String) {
      try {
        return Color(int.parse(value.replaceFirst('#', ''), radix: 16));
      } catch (_) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  void updateDigitColor(Color color) {
    emit(state.copyWith(digitColor: color));
  }

  void updateColonColor(Color color) {
    emit(state.copyWith(colonColor: color));
  }

  void updateBackgroundColor(Color color) {
    emit(state.copyWith(backgroundColor: color));
  }

  void toggleSeconds() {
    emit(state.copyWith(showSeconds: !state.showSeconds));
  }

  Future<void> save() async {
    emit(state.copyWith(isLoading: true));
    try {
      final config = getConfig();
      final updatedScreen = state.screen.copyWith(
        config: config,
        name: 'Digital Clock',
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
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Map<String, dynamic> getConfig() {
    return {
      'digitColor': state.digitColor.value,
      'colonColor': state.colonColor.value,
      'backgroundColor': state.backgroundColor.value,
      'showSeconds': state.showSeconds,
    };
  }
}
