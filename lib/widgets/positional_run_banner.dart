import 'package:flutter/material.dart';

import '../engine/positional_run_detector.dart';

class PositionalRunBanner extends StatelessWidget {
  final PositionalRunWarning warning;

  const PositionalRunBanner({super.key, required this.warning});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Colors.black87, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${warning.message} — ${warning.position} getting scarce',
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
