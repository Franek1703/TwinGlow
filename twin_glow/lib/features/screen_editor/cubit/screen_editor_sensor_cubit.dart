import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/screen_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class ScreenEditorSensorState {
  final ScreenModel screen;
  final bool showTemperature;
  final bool showHumidity;
  final bool showPressure;
  final bool useMetricUnits;
  final Color numberColor;
  final Color accentColor;
  final Color backgroundColor;
  final bool isLoading;
  final String? error;

  ScreenEditorSensorState({
    required this.screen,
    this.showTemperature = true,
    this.showHumidity = true,
    this.showPressure = false,
    this.useMetricUnits = true,
    this.numberColor = const Color(0xFF00D9FF),
    this.accentColor = const Color(0xFF7EF89E),
    this.backgroundColor = Colors.black,
    this.isLoading = false,
    this.error,
  });

  ScreenEditorSensorState copyWith({
    ScreenModel? screen,
    bool? showTemperature,
    bool? showHumidity,
    bool? showPressure,
    bool? useMetricUnits,
    Color? numberColor,
    Color? accentColor,
    Color? backgroundColor,
    bool? isLoading,
    String? error,
  }) {
    return ScreenEditorSensorState(
      screen: screen ?? this.screen,
      showTemperature: showTemperature ?? this.showTemperature,
      showHumidity: showHumidity ?? this.showHumidity,
      showPressure: showPressure ?? this.showPressure,
      useMetricUnits: useMetricUnits ?? this.useMetricUnits,
      numberColor: numberColor ?? this.numberColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ScreenEditorSensorCubit extends Cubit<ScreenEditorSensorState> {
  final FirebaseRepository firebaseRepository;
  final String deviceId;
  final bool isNewScreen;

  ScreenEditorSensorCubit(this.firebaseRepository, this.deviceId, ScreenModel screen)
      : isNewScreen = screen.config == null,
        super(ScreenEditorSensorState(
          screen: screen,
          showTemperature: screen.config?['showTemperature'] ?? true,
          showHumidity: screen.config?['showHumidity'] ?? true,
          showPressure: screen.config?['showPressure'] ?? false,
          useMetricUnits: screen.config?['useMetricUnits'] ?? true,
          numberColor: _getColorFromConfig(screen.config, 'numberColor', const Color(0xFF00D9FF)),
          accentColor: _getColorFromConfig(screen.config, 'accentColor', const Color(0xFF7EF89E)),
          backgroundColor: _getColorFromConfig(screen.config, 'backgroundColor', Colors.black),
        ));

  static Color _getColorFromConfig(Map<String, dynamic>? config, String key, Color defaultValue) {
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

  void toggleTemperature() {
    emit(state.copyWith(showTemperature: !state.showTemperature));
  }

  void toggleHumidity() {
    emit(state.copyWith(showHumidity: !state.showHumidity));
  }

  void togglePressure() {
    emit(state.copyWith(showPressure: !state.showPressure));
  }

  void toggleUnits() {
    emit(state.copyWith(useMetricUnits: !state.useMetricUnits));
  }

  void updateNumberColor(Color color) {
    emit(state.copyWith(numberColor: color));
  }

  void updateAccentColor(Color color) {
    emit(state.copyWith(accentColor: color));
  }

  void updateBackgroundColor(Color color) {
    emit(state.copyWith(backgroundColor: color));
  }

  Future<void> save() async {
    emit(state.copyWith(isLoading: true));
    try {
      final config = getConfig();
      final updatedScreen = state.screen.copyWith(
        config: config,
        name: 'Sensor Display',
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

  Map<String, dynamic> getConfig() {
    return {
      'showTemperature': state.showTemperature,
      'showHumidity': state.showHumidity,
      'showPressure': state.showPressure,
      'useMetricUnits': state.useMetricUnits,
      'numberColor': state.numberColor.value,
      'accentColor': state.accentColor.value,
      'backgroundColor': state.backgroundColor.value,
    };
  }
}
