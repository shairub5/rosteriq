import 'package:flutter/material.dart';

import '../models/player.dart';
import '../models/ranking_result.dart';
import '../state/stats_display_mode_provider.dart';
import '../state/team_names_provider.dart';
import 'player_avatar.dart';
import 'player_stat_row.dart';

class PlayerTile extends StatelessWidget {
  final Player player;
  final RankingResult ranking;
  final bool showPuntAdjusted;
  final bool showAdp;
  final StatLine displayStats;
  final StatsDisplayMode statsDisplayMode;
  final VoidCallback onDraftedByMe;
  final void Function(int teamSlot) onDraftedByOther;
  final int teamsCount;
  final int myDraftSlot;
  final Map<int, String> teamNames;
  final int? gamesThisWeek;
  final bool hasBackToBack;

  const PlayerTile({
    super.key,
    required this.player,
    required this.ranking,
    required this.showPuntAdjusted,
    this.showAdp = false,
    required this.displayStats,
    required this.statsDisplayMode,
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
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () => _showDraftSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlayerAvatar(
                  nbaId: player.nbaId,
                  playerName: player.name,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              player.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
                              child: Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${player.eligiblePositions.join(",")} · ${player.team}',
                            style: TextStyle(fontSize: 12, color: subtitleColor),
                          ),
                          if (gamesThisWeek != null) ...[
                            const SizedBox(width: 6),
                            _GamesThisWeekBadge(games: gamesThisWeek!),
                          ],
                          if (showAdp && player.adp != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              'ADP ${player.adp!.toStringAsFixed(1)}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.blueGrey),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    displayZ.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 42,
                  child: Text(
                    ranking.needAdjustedZ.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 4),
              child: PlayerStatRow(stats: displayStats, gp: player.gp, mode: statsDisplayMode),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDraftSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                player.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1, color: Colors.green),
              title: const Text('My pick'),
              onTap: () {
                Navigator.of(ctx).pop();
                onDraftedByMe();
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Drafted by another team:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            SizedBox(
              height: 200,
              child: ListView(
                children: [
                  for (var i = 1; i <= teamsCount; i++)
                    if (i != myDraftSlot)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.group_outlined, size: 20),
                        title: Text(displayNameForSlot(teamNames, i, myDraftSlot)),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onDraftedByOther(i);
                        },
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

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
