import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../features/auth/cubit/auth_cubit.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _nameController = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, authState) {
            final user = authState.user;
            
            if (user == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Not authenticated',
                      style: AppTypography.h2(context),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    AppButton(
                      text: 'Sign In',
                      onPressed: () => context.go('/auth'),
                    ),
                  ],
                ),
              );
            }

            if (!_isEditing && _nameController.text.isEmpty) {
              _nameController.text = user.displayName ?? '';
            }

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar Section
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 120.w,
                          height: 120.w,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentCyan.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.person,
                            size: 64.sp,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        Text(
                          user.displayName ?? 'User',
                          style: AppTypography.h1(context),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          user.email,
                          style: AppTypography.body(context),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSpacing.xxl),
                  // Profile Information
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Display Name',
                              style: AppTypography.h4(context),
                            ),
                            if (!_isEditing)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isEditing = true;
                                  });
                                },
                                child: Text(
                                  'Edit',
                                  style: TextStyle(
                                    color: AppColors.accentCyan,
                                    fontSize: 14.sp,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),
                        if (_isEditing)
                          Column(
                            children: [
                              AppInput(
                                controller: _nameController,
                                hint: 'Enter display name',
                              ),
                              SizedBox(height: AppSpacing.md),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _isEditing = false;
                                        _nameController.text = user.displayName ?? '';
                                      });
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 14.sp,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: AppSpacing.md),
                                  AppButton(
                                    text: 'Save',
                                    onPressed: () {
                                      // TODO: Update user display name via AuthCubit
                                      setState(() {
                                        _isEditing = false;
                                      });
                                    },
                                    size: AppButtonSize.sm,
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Text(
                            user.displayName ?? 'Not set',
                            style: AppTypography.body(context),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email',
                          style: AppTypography.h4(context),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          user.email,
                          style: AppTypography.body(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
