import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_typography.dart';

class AssetEditorImageView extends StatelessWidget {
  final String? assetId;

  const AssetEditorImageView({super.key, this.assetId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(assetId == null ? 'Create Image' : 'Edit Image'),
      ),
      body: Center(
        child: Text(
          assetId == null
              ? 'Create new image asset\nTODO: Implement pixel editor'
              : 'Edit image asset: $assetId\nTODO: Implement pixel editor',
          style: AppTypography.body(context),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
