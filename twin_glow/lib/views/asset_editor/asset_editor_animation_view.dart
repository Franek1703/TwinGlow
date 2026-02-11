import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_typography.dart';

class AssetEditorAnimationView extends StatelessWidget {
  const AssetEditorAnimationView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Create Animation'),
      ),
      body: Center(
        child: Text(
          'Create new animation asset\nTODO: Implement animation editor',
          style: AppTypography.body(context),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
