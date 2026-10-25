import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/stat_category.dart';

/// A 9-axis spider / radar chart visualising the user's team standing.
///
/// The bold middle ring is league average; farther out is better, closer to the
/// center is worse, scaled to the largest value shown.
/// The fill polygon uses a semi-transparent primary colour. An optional
/// [opponent] is drawn as an unfilled tertiary outline with vertex dots, so
/// the two teams differ by shape as well as hue, plus a legend.
///
/// Uses a custom [CustomPainter] so there are no extra package dependencies.
class CategoryRadarChart extends StatelessWidget {
  final Map<StatCategory, double> standing;
  final Set<StatCategory> puntedCategories;
  final Map<StatCategory, double>? opponent;
  final String opponentLabel;

  const CategoryRadarChart({
    super.key,
    required this.standing,
    required this.puntedCategories,
    this.opponent,
    this.opponentLabel = 'Opponent',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Explicit width: CustomPaint has no intrinsic size, so loose constraints (e.g. in a Column) would collapse it.
    final chart = SizedBox(
      width: double.infinity,
      height: 280,
      child: CustomPaint(
        painter: _RadarPainter(
          standing: standing,
          puntedCategories: puntedCategories,
          opponent: opponent,
          colors: colors,
        ),
      ),
    );
    if (opponent == null) return chart;
    return Column(
      children: [
        chart,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(color: colors.primary, label: 'You', filled: true),
            const SizedBox(width: 16),
            Flexible(child: _LegendItem(color: colors.tertiary, label: opponentLabel, filled: false)),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool filled;

  const _LegendItem({required this.color, required this.label, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.25) : null,
            border: Border.all(color: color, width: 2),
            shape: filled ? BoxShape.rectangle : BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Map<StatCategory, double> standing;
  final Set<StatCategory> puntedCategories;
  final Map<StatCategory, double>? opponent;
  final ColorScheme colors;

  _RadarPainter({
    required this.standing,
    required this.puntedCategories,
    required this.opponent,
    required this.colors,
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

    // Both teams share one scale: the middle ring is league average (0), the outer ring is the
    // largest |value| shown. Team totals range far wider than one player's z, so no fixed scale fits.
    final shown = [
      for (final m in [standing, ?opponent])
        for (final c in categories)
          if (!puntedCategories.contains(c)) (m[c] ?? 0).abs(),
    ];
    final scale = math.max(1.0, shown.fold(0.0, math.max));
    double zToFraction(double z) => 0.5 + 0.5 * (z / scale).clamp(-1.0, 1.0);

    // --- Reference rings; the bolder middle one is league average ---
    for (final fraction in const [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final pt = axisPoint(i, fraction);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = fraction == 0.5 ? colors.outline : colors.outlineVariant
          ..style = PaintingStyle.stroke
          ..strokeWidth = fraction == 0.5 ? 1.2 : 0.8,
      );
    }

    // --- Draw axes ---
    final axisPaint = Paint()
      ..color = colors.outline
      ..strokeWidth = 0.8;
    for (var i = 0; i < n; i++) {
      final outer = axisPoint(i, 1.0);
      canvas.drawLine(Offset(cx, cy), outer, axisPaint);
    }

    Path polygon(Map<StatCategory, double> values) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final pt = axisPoint(i, zToFraction(values[categories[i]] ?? 0));
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      return path..close();
    }

    // --- Draw team fill polygon ---
    final fillPath = polygon(standing);
    final primaryColor = colors.primary;

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

    // --- Opponent outline + vertex dots ---
    final opp = opponent;
    if (opp != null) {
      canvas.drawPath(
        polygon(opp),
        Paint()
          ..color = colors.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final dotPaint = Paint()..color = colors.tertiary;
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(axisPoint(i, zToFraction(opp[categories[i]] ?? 0)), 4, dotPaint);
      }
    }

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
            color: isPunted ? colors.outline : colors.onSurface,
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
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = colors.outline);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.standing != standing ||
      old.puntedCategories != puntedCategories ||
      old.opponent != opponent ||
      old.colors != colors;
}
