import 'package:flutter/material.dart';

import '../models/player.dart';
import '../state/stats_display_mode_provider.dart';

/// A compact single-line readout of a [StatLine]'s 9 categories, used on the
/// pool screen tiles. Kept as plain abbreviated text (not a table) so it
/// fits under a ListTile without blowing up row height.
class PlayerStatRow extends StatelessWidget {
  final StatLine stats;
  final int gp;
  final StatsDisplayMode mode;

  const PlayerStatRow({
    super.key,
    required this.stats,
    required this.gp,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final perGame = mode == StatsDisplayMode.perGame;
    final divisor = gp > 0 ? gp : 1;

    String fmt(int total) =>
        perGame ? (total / divisor).toStringAsFixed(1) : total.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FG% ${stats.fgPct.toStringAsFixed(3)}   FT% ${stats.ftPct.toStringAsFixed(3)}   '
          '3PM ${fmt(stats.threePM)}   PTS ${fmt(stats.pts)}',
          style: style,
        ),
        Text(
          'REB ${fmt(stats.reb)}   AST ${fmt(stats.ast)}   STL ${fmt(stats.stl)}   BLK ${fmt(stats.blk)}   TO ${fmt(stats.to)}',
          style: style,
        ),
      ],
    );
  }
}
