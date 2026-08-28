import 'package:flutter/material.dart';

import '../models/player.dart';
import '../models/ranking_result.dart';
import '../state/team_names_provider.dart';
import 'player_avatar.dart';
import 'player_stat_row.dart';

class PlayerTile extends StatelessWidget {
  final Player player;
  final RankingResult ranking;
  final bool showPuntAdjusted;
  final bool showAdp;
  final StatLine displayStats;
  final VoidCallback onDraftedByMe;
  final void Function(int teamSlot) onDraftedByOther;
  final int teamsCount;
  final int myDraftSlot;
  final Map<int, String> teamNames;

  /// Number of games the player's team plays during the current Mon–Sun week.
  /// Null when the schedule has not loaded yet.
  final int? gamesThisWeek;

  /// True when the player's team plays tonight AND tomorrow (back-to-back).
  /// Shows an orange "B2B" chip as a load-management risk indicator.
  final bool hasBackToBack;

  const PlayerTile({
    super.key,
    required this.player,
    required this.ranking,
    required this.showPuntAdjusted,
    this.showAdp = false,
    required this.displayStats,
    required this.onDraftedByMe,
    required this.onDraftedByOther,
    required this.teamsCount,
    required this.myDraftSlot,
    required this.teamNames,
    this.gamesThisWeek,
    this.hasBackToBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayZ = showPuntAdjusted ? ranking.puntAdjustedZ : ranking.totalZ;
    return ListTile(
      leading: PlayerAvatar(
        nbaId: player.nbaId,
        playerName: player.name,
        radius: 22,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              player.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasBackToBack)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: _B2BChip(),
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
          Row(
            children: [
              Text('${player.eligiblePositions.join(",")} · ${player.team}'),
              if (gamesThisWeek != null) ...[
                const SizedBox(width: 8),
                _GamesThisWeekBadge(games: gamesThisWeek!),
              ],
              if (showAdp) ...[
                const SizedBox(width: 8),
                Text(
                  player.adp != null ? 'ADP ${player.adp!.toStringAsFixed(1)}' : 'ADP -',
                  style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blueGrey),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          PlayerStatRow(stats: displayStats),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              displayZ.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              ranking.needAdjustedZ.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
            ),
          ),
          const SizedBox(width: 4),
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

/// Small colored chip showing how many games the team plays this week.
/// Green = 3+, yellow = 2, grey = 1 or 0.
class _GamesThisWeekBadge extends StatelessWidget {
  final int games;

  const _GamesThisWeekBadge({required this.games});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (games >= 3) {
      bg = Colors.green[700]!;
      fg = Colors.white;
    } else if (games == 2) {
      bg = Colors.amber[700]!;
      fg = Colors.white;
    } else {
      bg = Colors.grey[400]!;
      fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        '${games}G',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Orange "B2B" chip shown when the player's team plays tonight AND tomorrow.
class _B2BChip extends StatelessWidget {
  const _B2BChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.deepOrange[400],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'B2B',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}
