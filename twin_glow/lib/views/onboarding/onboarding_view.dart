import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  int _currentSlide = 0;

  final List<_SlideData> _slides = [
    _SlideData(
      icon: Icons.favorite,
      title: 'Welcome to TwinGlow',
      description:
          'A connected emotional display that brings you closer to the ones you love through shared moments and beautiful LED art.',
      gradient: AppColors.magentaGradient,
    ),
    _SlideData(
      icon: Icons.share,
      title: 'Screens & Sharing',
      description:
          'Create custom screen playlists with images, animations, clocks, and sensor data. Share special screens with your paired user.',
      gradient: AppColors.cyanGreenGradient,
    ),
    _SlideData(
      icon: Icons.bluetooth,
      title: 'Easy Setup',
      description:
          'Connect your TwinGlow device via Bluetooth, set up Wi-Fi, and start sharing beautiful moments in seconds.',
      gradient: AppColors.purpleCyanGradient,
    ),
  ];

  void _handleNext() {
    if (_currentSlide < _slides.length - 1) {
      setState(() {
        _currentSlide++;
      });
    } else {
      context.go('/auth');
    }
  }

  void _handleSkip() {
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentSlide];

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _handleSkip,
                  child: Text(
                    'Skip',
                    style: AppTypography.small(context).copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.xl),
              // Content
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    Container(
                      width: 128.w,
                      height: 128.w,
                      decoration: BoxDecoration(
                        gradient: slide.gradient,
                        borderRadius: BorderRadius.circular(AppSpacing.radius3xl),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentCyan.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        slide.icon,
                        size: 64.sp,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xxl),
                    // Title
                    Text(
                      slide.title,
                      style: AppTypography.h1(context),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Description
                    SizedBox(
                      width: 300.w,
                      child: Text(
                        slide.description,
                        style: AppTypography.body(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              // Pagination dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => Container(
                    margin: EdgeInsets.symmetric(horizontal: 4.w),
                    width: index == _currentSlide ? 32.w : 8.w,
                    height: 8.h,
                    decoration: BoxDecoration(
                      gradient: index == _currentSlide
                          ? AppColors.primaryGradient
                          : null,
                      color: index == _currentSlide
                          ? null
                          : AppColors.borderColor,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.xl),
              // CTA Button
              AppButton(
                text: _currentSlide == _slides.length - 1
                    ? 'Get Started'
                    : 'Next',
                onPressed: _handleNext,
                size: AppButtonSize.lg,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final String title;
  final String description;
  final LinearGradient gradient;

  _SlideData({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });
}
