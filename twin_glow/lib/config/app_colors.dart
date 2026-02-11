import 'package:flutter/material.dart';

/// TwinGlow color palette - dark theme
class AppColors {
  // Background colors
  static const Color bgPrimary = Color(0xFF0F1419);
  static const Color bgSecondary = Color(0xFF1A1F2E);
  static const Color bgCard = Color(0xFF1F2937);
  static const Color bgElevated = Color(0xFF252D3D);

  // Accent colors
  static const Color accentCyan = Color(0xFF00D9FF);
  static const Color accentMagenta = Color(0xFFFF006E);
  static const Color accentGreen = Color(0xFF7EF89E);
  static const Color accentPurple = Color(0xFFB794F6);

  // Text colors
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  // Border colors
  static const Color borderColor = Color(0xFF374151);
  static const Color borderSubtle = Color(0xFF2D3748);

  // Status colors
  static const Color statusOnline = Color(0xFF10B981);
  static const Color statusOffline = Color(0xFF6B7280);
  static const Color statusError = Color(0xFFEF4444);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentCyan, accentPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient magentaGradient = LinearGradient(
    colors: [accentMagenta, accentPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGreenGradient = LinearGradient(
    colors: [accentCyan, accentGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleCyanGradient = LinearGradient(
    colors: [accentPurple, accentCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
