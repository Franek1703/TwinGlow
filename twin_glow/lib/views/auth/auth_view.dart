import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_input.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../services/firebase/firebase_fake_repository.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLogin = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSubmit(AuthCubit cubit) {
    if (_formKey.currentState!.validate()) {
      if (_isLogin) {
        cubit.signIn(_emailController.text, _passwordController.text);
      } else {
        cubit.signUp(_emailController.text, _passwordController.text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(FirebaseFakeRepository()),
      child: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state.isAuthenticated) {
            // Check if user has devices, if not go to provisioning
            context.go('/home'); // TODO: Check devices and route accordingly
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxl,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    SizedBox(height: AppSpacing.xxl),
                    // Logo/Header
                    Column(
                      children: [
                        Container(
                          width: 80.w,
                          height: 80.w,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusXl),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentCyan.withOpacity(0.3),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                            ),
                            itemCount: 16,
                            itemBuilder: (context, index) => Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: AppSpacing.lg),
                        Text(
                          'TwinGlow',
                          style: AppTypography.h1(context),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'Connected emotional displays',
                          style: AppTypography.body(context).copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.xxl),
                    // Form fields
                    Expanded(
                      child: Column(
                        children: [
                          AppInput(
                            label: 'Email',
                            hint: 'your@email.com',
                            icon: Icon(Icons.mail, size: 20.sp),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: AppSpacing.lg),
                          AppInput(
                            label: 'Password',
                            hint: '••••••••',
                            icon: Icon(Icons.lock, size: 20.sp),
                            controller: _passwordController,
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          if (!_isLogin) ...[
                            SizedBox(height: AppSpacing.lg),
                            AppInput(
                              label: 'Confirm Password',
                              hint: '••••••••',
                              icon: Icon(Icons.lock, size: 20.sp),
                              controller: _confirmPasswordController,
                              obscureText: true,
                              validator: (value) {
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],
                          if (_isLogin) ...[
                            SizedBox(height: AppSpacing.md),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () {
                                  // TODO: Implement forgot password
                                },
                                child: Text(
                                  'Forgot password?',
                                  style: AppTypography.small(context).copyWith(
                                    color: AppColors.accentCyan,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Submit button
                    BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) {
                        return AppButton(
                          text: _isLogin ? 'Sign In' : 'Create Account',
                          onPressed: state.isLoading
                              ? null
                              : () => _handleSubmit(context.read<AuthCubit>()),
                          size: AppButtonSize.lg,
                          fullWidth: true,
                          isLoading: state.isLoading,
                        );
                      },
                    ),
                    SizedBox(height: AppSpacing.lg),
                    // Toggle login/signup
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLogin = !_isLogin;
                        });
                      },
                      child: RichText(
                        text: TextSpan(
                          style: AppTypography.small(context).copyWith(
                            color: AppColors.textMuted,
                          ),
                          children: [
                            TextSpan(
                              text: _isLogin
                                  ? "Don't have an account? "
                                  : "Already have an account? ",
                            ),
                            TextSpan(
                              text: _isLogin ? 'Sign up' : 'Sign in',
                              style: TextStyle(
                                color: AppColors.accentCyan,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
