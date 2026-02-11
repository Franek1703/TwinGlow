import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_typography.dart';

class ScreenEditorSensorView extends StatelessWidget {
  final String screenId;

  const ScreenEditorSensorView({super.key, required this.screenId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Sensor Screen Editor'),
      ),
      body: Center(
        child: Text(
          'Sensor Editor for screen: $screenId\nTODO: Implement sensor screen configuration',
          style: AppTypography.body(context),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
