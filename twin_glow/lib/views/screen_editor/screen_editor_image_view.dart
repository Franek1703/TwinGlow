import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_typography.dart';

class ScreenEditorImageView extends StatelessWidget {
  final String screenId;

  const ScreenEditorImageView({super.key, required this.screenId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Image Screen Editor'),
      ),
      body: Center(
        child: Text(
          'Image Editor for screen: $screenId\nTODO: Implement image screen configuration',
          style: AppTypography.body(context),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
