import 'package:flutter/material.dart';

import '../models/player.dart';
import '../models/ranking_result.dart';
import '../state/team_names_provider.dart';
import 'player_stat_row.dart';

class PlayerTile extends StatelessWidget {
  final Player player;
  final RankingResult ranking;
  final bool showPuntAdjusted;
  final StatLine displayStats;
  final VoidCallback onDraftedByMe;
  final void Function(int teamSlot) onDraftedByOther;
  final int teamsCount;
  final int myDraftSlot;
  final Map<int, String> teamNames;

  const PlayerTile({
    super.key,
    required this.player,
    required this.ranking,
    required this.showPuntAdjusted,
    required this.displayStats,
    required this.onDraftedByMe,
    required this.onDraftedByOther,
    required this.teamsCount,
    required this.myDraftSlot,
    required this.teamNames,
  });

  @override
  Widget build(BuildContext context) {
    final displayZ = showPuntAdjusted ? ranking.puntAdjustedZ : ranking.totalZ;
    return ListTile(
      leading: CircleAvatar(child: Text('${ranking.rank}')),
      title: Row(
        children: [
          Expanded(
            child: Text(
              player.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ranking.rosterFitWarning)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${player.eligiblePositions.join(",")} · ${player.team}'),
          const SizedBox(height: 2),
          PlayerStatRow(stats: displayStats),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayZ.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: Colors.green),
            tooltip: 'Drafted by me',
            onPressed: onDraftedByMe,
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
            tooltip: 'Drafted by another team',
            onPressed: () => _pickOtherTeam(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOtherTeam(BuildContext context) async {
    final slot = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (var i = 1; i <= teamsCount; i++)
            if (i != myDraftSlot)
              ListTile(
                title: Text(displayNameForSlot(teamNames, i, myDraftSlot)),
                onTap: () => Navigator.of(context).pop(i),
              ),
        ],
      ),
    );
    if (slot != null) onDraftedByOther(slot);
  }
}
