import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Displays a 16x16 pixel grid preview
class PixelPreview extends StatelessWidget {
  final List<List<int>> data; // 16x16 grid of RGB colors

  const PixelPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: EdgeInsets.all(AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A pixel matrix must stay square. The old GridView used the full
          // card width even in a short preview, clipping its bottom rows.
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 16,
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 1,
                ),
                itemCount: 256, // 16x16
                itemBuilder: (context, index) {
                  final row = index ~/ 16;
                  final col = index % 16;
                  final colorValue = row < data.length && col < data[row].length
                      ? data[row][col]
                      : 0;

                  Color color;
                  if (colorValue == 0) {
                    color = Colors.black;
                  } else {
                    final r = (colorValue >> 16) & 0xFF;
                    final g = (colorValue >> 8) & 0xFF;
                    final b = colorValue & 0xFF;
                    color = Color.fromRGBO(r, g, b, 1);
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
