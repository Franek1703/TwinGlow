import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

enum DrawingTool {
  pencil,
  eraser,
  fill,
}

class PixelGridEditor extends StatefulWidget {
  final List<List<int>>? initialData;
  final Color currentColor;
  final DrawingTool currentTool;
  final ValueChanged<List<List<int>>> onDataChanged;

  const PixelGridEditor({
    super.key,
    this.initialData,
    required this.currentColor,
    required this.currentTool,
    required this.onDataChanged,
  });

  @override
  State<PixelGridEditor> createState() => _PixelGridEditorState();
}

class _PixelGridEditorState extends State<PixelGridEditor> {
  late List<List<int>> _grid;
  bool _isDrawing = false;

  @override
  void initState() {
    super.initState();
    _grid = widget.initialData ?? _createEmptyGrid();
  }

  List<List<int>> _createEmptyGrid() {
    return List.generate(16, (_) => List.filled(16, 0));
  }

  void _handlePixelTap(int row, int col) {
    setState(() {
      if (widget.currentTool == DrawingTool.pencil) {
        _grid[row][col] = widget.currentColor.value;
      } else if (widget.currentTool == DrawingTool.eraser) {
        _grid[row][col] = 0;
      } else if (widget.currentTool == DrawingTool.fill) {
        _fillArea(row, col, _grid[row][col], widget.currentColor.value);
      }
      widget.onDataChanged(_grid);
    });
  }

  void _handlePixelDrag(int row, int col) {
    if (!_isDrawing) return;
    setState(() {
      if (widget.currentTool == DrawingTool.pencil) {
        _grid[row][col] = widget.currentColor.value;
      } else if (widget.currentTool == DrawingTool.eraser) {
        _grid[row][col] = 0;
      }
      widget.onDataChanged(_grid);
    });
  }

  void _fillArea(int startRow, int startCol, int targetColor, int fillColor) {
    if (targetColor == fillColor) return;

    final queue = <List<int>>[];
    queue.add([startRow, startCol]);

    while (queue.isNotEmpty) {
      final pos = queue.removeAt(0);
      final r = pos[0];
      final c = pos[1];

      if (r < 0 || r >= 16 || c < 0 || c >= 16) continue;
      if (_grid[r][c] != targetColor) continue;

      _grid[r][c] = fillColor;

      queue.add([r - 1, c]);
      queue.add([r + 1, c]);
      queue.add([r, c - 1]);
      queue.add([r, c + 1]);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 16,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
        ),
        itemCount: 256, // 16x16
        itemBuilder: (context, index) {
          final row = index ~/ 16;
          final col = index % 16;
          final colorValue = _grid[row][col];

          Color color;
          if (colorValue == 0) {
            color = Colors.black;
          } else {
            final r = (colorValue >> 16) & 0xFF;
            final g = (colorValue >> 8) & 0xFF;
            final b = colorValue & 0xFF;
            color = Color.fromRGBO(r, g, b, 1);
          }

          return GestureDetector(
            onTapDown: (_) {
              _isDrawing = true;
              _handlePixelTap(row, col);
            },
            onTapUp: (_) => _isDrawing = false,
            onTapCancel: () => _isDrawing = false,
            onPanUpdate: (details) {
              final renderBox = context.findRenderObject() as RenderBox?;
              if (renderBox == null) return;
              final localPosition = renderBox.globalToLocal(details.localPosition);
              final cellSize = renderBox.size.width / 16;
              final newRow = (localPosition.dy / cellSize).floor();
              final newCol = (localPosition.dx / cellSize).floor();
              if (newRow >= 0 && newRow < 16 && newCol >= 0 && newCol < 16) {
                _handlePixelDrag(newRow, newCol);
              }
            },
            onPanEnd: (_) => _isDrawing = false,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
                border: Border.all(
                  color: AppColors.borderSubtle.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
