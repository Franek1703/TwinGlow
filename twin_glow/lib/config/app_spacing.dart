import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Spacing tokens for consistent layout
class AppSpacing {
  // Base spacing unit (4px)
  static double get xs => 4.w;
  static double get sm => 8.w;
  static double get md => 12.w;
  static double get lg => 16.w;
  static double get xl => 24.w;
  static double get xxl => 32.w;
  static double get xxxl => 48.w;

  // Specific spacing values
  static double get spacing1 => 4.w;
  static double get spacing2 => 8.w;
  static double get spacing3 => 12.w;
  static double get spacing4 => 16.w;
  static double get spacing6 => 24.w;
  static double get spacing8 => 32.w;
  static double get spacing12 => 48.w;
  static double get spacing16 => 64.w;
  static double get spacing24 => 96.w;

  // Border radius
  static double get radiusSm => 4.r;
  static double get radiusMd => 8.r;
  static double get radiusLg => 12.r;
  static double get radiusXl => 16.r;
  static double get radius2xl => 24.r;
  static double get radius3xl => 32.r;
  static double get radiusFull => 9999.r;
}
