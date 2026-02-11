import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../features/pairing/cubit/pairing_cubit.dart';
import '../../services/firebase/firebase_fake_repository.dart';

class PairingManagementView extends StatefulWidget {
  const PairingManagementView({super.key});

  @override
  State<PairingManagementView> createState() => _PairingManagementViewState();
}

class _PairingManagementViewState extends State<PairingManagementView> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Get userId from AuthCubit
    const userId = 'user1';

    return BlocProvider(
      create: (_) => PairingCubit(FirebaseFakeRepository(), userId),
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(
          title: const Text('Pairing Management'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: BlocBuilder<PairingCubit, PairingState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      'Pairing',
                      style: AppTypography.h1(context),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Text(
                      'Connect with another user to share screens',
                      style: AppTypography.body(context),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Current Pairing Status
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                state.pairing != null
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: state.pairing != null
                                    ? AppColors.accentMagenta
                                    : AppColors.textMuted,
                                size: 24.sp,
                              ),
                              SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.pairing != null
                                          ? 'Paired'
                                          : 'Not Paired',
                                      style: AppTypography.h3(context),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      state.pairing != null
                                          ? '${state.pairing!.sharedScreensCount} shared screens'
                                          : 'No active pairing',
                                      style: AppTypography.small(context),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (state.pairing != null) ...[
                            SizedBox(height: AppSpacing.lg),
                            AppButton(
                              text: 'Unpair',
                              onPressed: () {
                                _showUnpairDialog(context);
                              },
                              variant: AppButtonVariant.danger,
                              fullWidth: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Invite User Section
                    Text(
                      'Invite User',
                      style: AppTypography.h2(context),
                    ),
                    SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send Pairing Invite',
                            style: AppTypography.h4(context),
                          ),
                          SizedBox(height: AppSpacing.md),
                          AppInput(
                            controller: _emailController,
                            label: 'Email Address',
                            hint: 'user@example.com',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          SizedBox(height: AppSpacing.md),
                          AppButton(
                            text: 'Send Invite',
                            onPressed: () {
                              if (_emailController.text.isNotEmpty) {
                                context
                                    .read<PairingCubit>()
                                    .sendInvite(_emailController.text.trim());
                                _emailController.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Invite sent to ${_emailController.text}'),
                                    backgroundColor: AppColors.accentGreen,
                                  ),
                                );
                              }
                            },
                            fullWidth: true,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    // Pending Invites (mock for now)
                    if (false) ...[
                      Text(
                        'Pending Invites',
                        style: AppTypography.h2(context),
                      ),
                      SizedBox(height: AppSpacing.md),
                      ...[].map((invite) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.md),
                          child: AppCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        invite,
                                        style: AppTypography.h4(context),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        'Waiting for acceptance',
                                        style: AppTypography.small(context),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    // TODO: Implement cancelInvite
                                  },
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showUnpairDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          'Unpair',
          style: AppTypography.h3(context),
        ),
        content: Text(
          'Are you sure you want to unpair? This will remove all shared screens.',
          style: AppTypography.body(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<PairingCubit>().unpair();
              Navigator.of(dialogContext).pop();
            },
            child: Text(
              'Unpair',
              style: TextStyle(color: AppColors.statusError),
            ),
          ),
        ],
      ),
    );
  }
}
