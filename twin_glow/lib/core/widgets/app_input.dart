import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';

class AppInput extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? error;
  final Widget? icon;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  const AppInput({
    super.key,
    this.label,
    this.hint,
    this.error,
    this.icon,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.validator,
  });

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final isPassword = widget.obscureText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTypography.label(context),
          ),
          SizedBox(height: AppSpacing.sm),
        ],
        Stack(
          children: [
            TextFormField(
              controller: widget.controller,
              obscureText: isPassword && _obscureText,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              validator: widget.validator,
              style: AppTypography.body(context).copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppTypography.body(context).copyWith(
                  color: AppColors.textMuted,
                ),
                prefixIcon: widget.icon != null
                    ? Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: widget.icon,
                      )
                    : null,
                prefixIconConstraints: widget.icon != null
                    ? BoxConstraints(minWidth: 48.w, minHeight: 48.w)
                    : null,
                suffixIcon: isPassword
                    ? IconButton(
                        icon: Icon(
                          _obscureText ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textMuted,
                          size: 20.sp,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureText = !_obscureText;
                          });
                        },
                      )
                    : null,
                errorText: widget.error,
                errorStyle: TextStyle(
                  color: AppColors.statusError,
                  fontSize: 12.sp,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
