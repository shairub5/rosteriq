import 'package:flutter/material.dart';

import '../models/stat_category.dart';

/// One row per category showing the user's current team z-score total as a
/// centered bar - green/right for strong, red/left for weak. Uses the same
/// z-score values the ranking engine computes, just visualized differently.
class CategoryStandingBar extends StatelessWidget {
  final Map<StatCategory, double> standing;
  final Set<StatCategory> puntedCategories;

  const CategoryStandingBar({super.key, required this.standing, required this.puntedCategories});

  @override
  Widget build(BuildContext context) {
    final maxAbs = standing.values.fold<double>(1, (m, v) => v.abs() > m ? v.abs() : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in allStatCategories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    category.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: puntedCategories.contains(category) ? TextDecoration.lineThrough : null,
                      color: puntedCategories.contains(category) ? Colors.grey : null,
                    ),
                  ),
                ),
                Expanded(child: _Bar(value: standing[category] ?? 0, maxAbs: maxAbs)),
                SizedBox(
                  width: 48,
                  child: Text(
                    (standing[category] ?? 0).toStringAsFixed(1),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double maxAbs;

  const _Bar({required this.value, required this.maxAbs});

  @override
  Widget build(BuildContext context) {
    final fraction = (value.abs() / maxAbs).clamp(0.0, 1.0);
    final positive = value >= 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfWidth = constraints.maxWidth / 2;
        final barWidth = halfWidth * fraction;
        return SizedBox(
          height: 14,
          child: Stack(
            children: [
              Positioned(
                left: positive ? halfWidth : halfWidth - barWidth,
                width: barWidth,
                top: 0,
                bottom: 0,
                child: Container(color: positive ? Colors.green : Colors.red),
              ),
              Positioned(
                left: halfWidth - 1,
                width: 2,
                top: 0,
                bottom: 0,
                child: Container(color: Colors.grey.shade400),
              ),
            ],
          ),
        );
      },
    );
  }
}
