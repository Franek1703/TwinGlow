import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_typography.dart';

class ScreenEditorClockView extends StatelessWidget {
  final String screenId;

  const ScreenEditorClockView({super.key, required this.screenId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Clock Screen Editor'),
      ),
      body: Center(
        child: Text(
          'Clock Editor for screen: $screenId\nTODO: Implement clock configuration',
          style: AppTypography.body(context),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
