import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/models/screen_model.dart';
import '../../core/widgets/app_card.dart';

class ScreenCreationView extends StatelessWidget {
  const ScreenCreationView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Create New Screen'),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Screen Type',
                style: AppTypography.h2(context),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Choose the type of screen you want to add to your playlist',
                style: AppTypography.body(context),
              ),
              SizedBox(height: AppSpacing.xl),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.lg,
                  mainAxisSpacing: AppSpacing.lg,
                  childAspectRatio: 0.9,
                  children: [
                    _ScreenTypeCard(
                      type: ScreenType.clock,
                      icon: Icons.access_time,
                      title: 'Clock',
                      description: 'Digital clock display',
                      onTap: () {
                        // Generate new screen ID and navigate to editor
                        final newId = 'screen_${DateTime.now().millisecondsSinceEpoch}';
                        context.go('/screen/clock/$newId');
                      },
                    ),
                    _ScreenTypeCard(
                      type: ScreenType.image,
                      icon: Icons.image,
                      title: 'Image',
                      description: 'Static image display',
                      onTap: () {
                        final newId = 'screen_${DateTime.now().millisecondsSinceEpoch}';
                        context.go('/screen/image/$newId');
                      },
                    ),
                    _ScreenTypeCard(
                      type: ScreenType.animation,
                      icon: Icons.movie,
                      title: 'Animation',
                      description: 'Animated sequence',
                      onTap: () {
                        final newId = 'screen_${DateTime.now().millisecondsSinceEpoch}';
                        context.go('/screen/animation/$newId');
                      },
                    ),
                    _ScreenTypeCard(
                      type: ScreenType.sensor,
                      icon: Icons.device_thermostat,
                      title: 'Sensor',
                      description: 'Sensor data display',
                      onTap: () {
                        final newId = 'screen_${DateTime.now().millisecondsSinceEpoch}';
                        context.go('/screen/sensor/$newId');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenTypeCard extends StatelessWidget {
  final ScreenType type;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ScreenTypeCard({
    required this.type,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      hoverable: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64.w,
            height: 64.w,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Icon(
              icon,
              size: 32.sp,
              color: Colors.white,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: AppTypography.h4(context),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: AppTypography.small(context),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
