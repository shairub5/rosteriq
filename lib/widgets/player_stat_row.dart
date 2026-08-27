import 'package:flutter/material.dart';

import '../models/player.dart';

/// A compact single-line readout of a [StatLine]'s 9 categories, used on the
/// pool screen tiles. Kept as plain abbreviated text (not a table) so it
/// fits under a ListTile without blowing up row height.
class PlayerStatRow extends StatelessWidget {
  final StatLine stats;

  const PlayerStatRow({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FG% ${stats.fgPct.toStringAsFixed(3)}   FT% ${stats.ftPct.toStringAsFixed(3)}   '
          '3PM ${stats.threePM}   PTS ${stats.pts}',
          style: style,
        ),
        Text(
          'REB ${stats.reb}   AST ${stats.ast}   STL ${stats.stl}   BLK ${stats.blk}   TO ${stats.to}',
          style: style,
        ),
      ],
    );
  }
}
