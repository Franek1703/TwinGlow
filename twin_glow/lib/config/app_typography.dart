import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Typography styles for TwinGlow app
class AppTypography {
  // Headings
  static TextStyle h1(BuildContext context) => TextStyle(
        fontSize: 28.sp,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.02,
        color: Colors.white,
      );

  static TextStyle h2(BuildContext context) => TextStyle(
        fontSize: 24.sp,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.01,
        color: Colors.white,
      );

  static TextStyle h3(BuildContext context) => TextStyle(
        fontSize: 18.sp,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: Colors.white,
      );

  static TextStyle h4(BuildContext context) => TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: Colors.white,
      );

  // Body text
  static TextStyle body(BuildContext context) => TextStyle(
        fontSize: 15.sp,
        height: 1.6,
        color: const Color(0xFF9CA3AF),
      );

  // Small text
  static TextStyle small(BuildContext context) => TextStyle(
        fontSize: 14.sp,
        height: 1.5,
        color: const Color(0xFF9CA3AF),
      );

  static TextStyle xs(BuildContext context) => TextStyle(
        fontSize: 12.sp,
        height: 1.5,
        color: const Color(0xFF9CA3AF),
      );

  // Labels
  static TextStyle label(BuildContext context) => TextStyle(
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF9CA3AF),
      );

  // Button text
  static TextStyle button(BuildContext context) => TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      );

  static TextStyle buttonSmall(BuildContext context) => TextStyle(
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      );

  static TextStyle buttonLarge(BuildContext context) => TextStyle(
        fontSize: 18.sp,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      );
}
