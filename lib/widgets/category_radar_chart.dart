import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/stat_category.dart';

/// A 9-axis spider / radar chart visualising the user's team standing.
///
/// Center = 0 (league average), outer ring = +3 (excellent), inner ring = -3.
/// Values are clamped to ±4 so extreme outliers don't distort the shape.
/// The fill polygon uses a semi-transparent primary colour.
///
/// Uses a custom [CustomPainter] so there are no extra package dependencies.
class CategoryRadarChart extends StatelessWidget {
  final Map<StatCategory, double> standing;
  final Set<StatCategory> puntedCategories;

  const CategoryRadarChart({
    super.key,
    required this.standing,
    required this.puntedCategories,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 280,
      child: CustomPaint(
        painter: _RadarPainter(
          standing: standing,
          puntedCategories: puntedCategories,
          primaryColor: color,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Map<StatCategory, double> standing;
  final Set<StatCategory> puntedCategories;
  final Color primaryColor;

  static const double _clampMax = 4.0;
  // Reference rings at ±1, ±2, ±3 z-score steps.
  static const List<double> _rings = [1, 2, 3];
  // Outer edge corresponds to +3 z units on the chart.
  static const double _outerZ = 3.0;

  _RadarPainter({
    required this.standing,
    required this.puntedCategories,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final categories = allStatCategories;
    final n = categories.length; // 9
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Leave room around the chart for labels.
    final radius = math.min(cx, cy) * 0.72;

    // Helper: angle for axis i (start at top, go clockwise).
    double axisAngle(int i) => -math.pi / 2 + (2 * math.pi * i / n);

    // Helper: (x, y) on axis i at a given fraction of the outer radius.
    Offset axisPoint(int i, double fraction) {
      final angle = axisAngle(i);
      return Offset(cx + radius * fraction * math.cos(angle), cy + radius * fraction * math.sin(angle));
    }

    // Helper: convert a z-score to a radius fraction (0 at center, 1 at outer).
    // Center = 0z, outer edge = _outerZ.
    double zToFraction(double z) => (z.clamp(-_clampMax, _clampMax) / _outerZ).clamp(-1.0, 1.0);

    // --- Draw reference rings (for ±1, ±2, ±3) ---
    final ringPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final ringZ in _rings) {
      final fraction = ringZ / _outerZ;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final pt = axisPoint(i, fraction);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(path, ringPaint);

      // Negative ring (inner, dashed-style — drawn with lower opacity).
      final negPath = Path();
      for (var i = 0; i < n; i++) {
        final pt = axisPoint(i, -fraction);
        i == 0 ? negPath.moveTo(pt.dx, pt.dy) : negPath.lineTo(pt.dx, pt.dy);
      }
      negPath.close();
      canvas.drawPath(negPath, ringPaint..color = Colors.grey.shade200);
    }

    // --- Draw axes ---
    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 0.8;
    for (var i = 0; i < n; i++) {
      final outer = axisPoint(i, 1.0);
      canvas.drawLine(Offset(cx, cy), outer, axisPaint);
    }

    // --- Draw team fill polygon ---
    final fillPath = Path();
    final values = categories.map((c) => standing[c] ?? 0).toList();
    for (var i = 0; i < n; i++) {
      final fraction = zToFraction(values[i]);
      final pt = axisPoint(i, fraction);
      i == 0 ? fillPath.moveTo(pt.dx, pt.dy) : fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // --- Axis labels ---
    for (var i = 0; i < n; i++) {
      final cat = categories[i];
      final isPunted = puntedCategories.contains(cat);
      final labelFraction = 1.22;
      final labelPt = axisPoint(i, labelFraction);

      final textPainter = TextPainter(
        text: TextSpan(
          text: cat.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isPunted ? Colors.grey.shade400 : Colors.black87,
            decoration: isPunted ? TextDecoration.lineThrough : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(labelPt.dx - textPainter.width / 2, labelPt.dy - textPainter.height / 2),
      );
    }

    // --- Center dot ---
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.grey.shade400);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.standing != standing ||
      old.puntedCategories != puntedCategories ||
      old.primaryColor != primaryColor;
}
