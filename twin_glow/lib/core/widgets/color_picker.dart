import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_typography.dart';
import 'app_card.dart';

class ColorPicker extends StatefulWidget {
  final Color initialColor;
  final String label;
  final ValueChanged<Color> onColorChanged;

  const ColorPicker({
    super.key,
    required this.initialColor,
    required this.label,
    required this.onColorChanged,
  });

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: AppTypography.h4(context),
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              // Color preview
              GestureDetector(
                onTap: _showColorPickerDialog,
                child: Container(
                  width: 60.w,
                  height: 60.w,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(
                      color: AppColors.borderColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.md),
              // Hex input
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hex',
                      style: AppTypography.small(context).copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Text(
                        '#${_selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                        style: AppTypography.body(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          // Preset colors
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _getPresetColors().map((color) {
              final isSelected = color.value == _selectedColor.value;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedColor = color;
                  });
                  widget.onColorChanged(color);
                },
                child: Container(
                  width: 32.w,
                  height: 32.w,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.accentCyan : AppColors.borderColor,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showColorPickerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          'Select Color',
          style: AppTypography.h3(context),
        ),
        content: SizedBox(
          width: 300.w,
          child: ColorPickerDialog(
            initialColor: _selectedColor,
            onColorChanged: (color) {
              setState(() {
                _selectedColor = color;
              });
              widget.onColorChanged(color);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Done',
              style: TextStyle(color: AppColors.accentCyan),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _getPresetColors() {
    // Fully saturated primaries rather than the Material swatches. Colors.red is
    // #F44336 - on a 16x16 LED panel its green and blue channels leave it looking
    // washed out next to a pure #FF0000, even though the firmware's gamma
    // correction now reproduces it faithfully.
    return [
      Colors.white,
      Colors.black,
      AppColors.accentCyan,
      AppColors.accentMagenta,
      AppColors.accentGreen,
      AppColors.accentPurple,
      const Color(0xFFFF0000),
      const Color(0xFFFF7F00),
      const Color(0xFFFFFF00),
      const Color(0xFF0000FF),
    ];
  }
}

class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // RGB sliders
        _ColorSlider(
          label: 'Red',
          value: _color.red.toDouble(),
          color: Colors.red,
          onChanged: (value) {
            setState(() {
              _color = Color.fromRGBO(value.toInt(), _color.green, _color.blue, 1);
            });
            widget.onColorChanged(_color);
          },
        ),
        SizedBox(height: AppSpacing.md),
        _ColorSlider(
          label: 'Green',
          value: _color.green.toDouble(),
          color: Colors.green,
          onChanged: (value) {
            setState(() {
              _color = Color.fromRGBO(_color.red, value.toInt(), _color.blue, 1);
            });
            widget.onColorChanged(_color);
          },
        ),
        SizedBox(height: AppSpacing.md),
        _ColorSlider(
          label: 'Blue',
          value: _color.blue.toDouble(),
          color: Colors.blue,
          onChanged: (value) {
            setState(() {
              _color = Color.fromRGBO(_color.red, _color.green, value.toInt(), 1);
            });
            widget.onColorChanged(_color);
          },
        ),
        SizedBox(height: AppSpacing.lg),
        // Preview
        Container(
          width: double.infinity,
          height: 60.h,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.borderColor),
          ),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _ColorSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.small(context),
            ),
            Text(
              value.toInt().toString(),
              style: AppTypography.small(context).copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        Slider(
          value: value,
          min: 0,
          max: 255,
          activeColor: color,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
