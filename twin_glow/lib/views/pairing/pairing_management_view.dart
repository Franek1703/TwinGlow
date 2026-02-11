import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_typography.dart';

class PairingManagementView extends StatelessWidget {
  const PairingManagementView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Pairing Management'),
      ),
      body: Center(
        child: Text(
          'Pairing Management\nTODO: Implement pairing invite/accept/unpair',
          style: AppTypography.body(context),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
