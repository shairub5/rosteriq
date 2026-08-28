import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/schedule_service.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import '../state/schedule_provider.dart';
import 'settings_screen.dart';

/// Ranks all available players by games in the fantasy playoff window, grouped
/// into tiers. Helps identify which players to prioritize if you're building
/// for a strong playoff push.
class PlayoffScheduleScreen extends ConsumerWidget {
  const PlayoffScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider);
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return scheduleAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) =>
          Scaffold(body: Center(child: Text('Failed to load schedule: $err'))),
      data: (schedule) => leagueDataAsync.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (err, _) =>
            Scaffold(body: Center(child: Text('Failed to load player data: $err'))),
        data: (leagueData) {
          final rankings = ref.watch(rankingsProvider);
          final playersById = ref.watch(playersByIdProvider);

          // Build per-player playoff stats for available pool only.
          final entries = <_PlayoffEntry>[];
          for (final ranking in rankings) {
            final player = playersById[ranking.playerId];
            if (player == null) continue;
            final teamSched = schedule.teams[player.team];
            final playoffGames = teamSched?.gamesInWindow(
                  schedule.fantasyPlayoffStart,
                  schedule.fantasyPlayoffEnd,
                ) ??
                0;
            final playoffB2Bs = teamSched == null
                ? 0
                : _countB2BsInWindow(
                    teamSched,
                    schedule.fantasyPlayoffStart,
                    schedule.fantasyPlayoffEnd,
                  );
            entries.add(_PlayoffEntry(
              name: player.name,
              team: player.team,
              positions: player.eligiblePositions,
              playoffGames: playoffGames,
              playoffB2Bs: playoffB2Bs,
              totalZ: ranking.totalZ,
            ));
          }

          // Sort by playoff games desc, then z desc.
          entries.sort((a, b) {
            final cmp = b.playoffGames.compareTo(a.playoffGames);
            return cmp != 0 ? cmp : b.totalZ.compareTo(a.totalZ);
          });

          // Group into tiers.
          final elite = entries.where((e) => e.playoffGames >= 15).toList();
          final good = entries.where((e) => e.playoffGames >= 13 && e.playoffGames <= 14).toList();
          final average = entries.where((e) => e.playoffGames >= 11 && e.playoffGames <= 12).toList();
          final weak = entries.where((e) => e.playoffGames < 11).toList();

          return Scaffold(
            appBar: AppBar(
              title: const Text('Playoff Schedule'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_fmt(schedule.fantasyPlayoffStart)} – ${_fmt(schedule.fantasyPlayoffEnd)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
              ),
            ),
            body: ListView(
              children: [
                if (elite.isNotEmpty)
                  ..._buildTier(context, 'Elite — 15+ games', elite, Colors.green[700]!),
                if (good.isNotEmpty)
                  ..._buildTier(context, 'Good — 13-14 games', good, Colors.teal[600]!),
                if (average.isNotEmpty)
                  ..._buildTier(context, 'Average — 11-12 games', average, Colors.orange[700]!),
                if (weak.isNotEmpty)
                  ..._buildTier(context, 'Weak — <11 games', weak, Colors.red[400]!),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildTier(
    BuildContext context,
    String title,
    List<_PlayoffEntry> entries,
    Color color,
  ) {
    return [
      Container(
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
      ),
      for (final e in entries) _PlayoffEntryTile(entry: e),
    ];
  }

  String _fmt(DateTime dt) =>
      '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
}

int _countB2BsInWindow(TeamSchedule sched, DateTime start, DateTime end) {
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  return sched.backToBacks
      .where((b) {
        final d = DateTime(b.year, b.month, b.day);
        return !d.isBefore(startDay) && !d.isAfter(endDay);
      })
      .length;
}

class _PlayoffEntry {
  final String name;
  final String team;
  final List<String> positions;
  final int playoffGames;
  final int playoffB2Bs;
  final double totalZ;

  const _PlayoffEntry({
    required this.name,
    required this.team,
    required this.positions,
    required this.playoffGames,
    required this.playoffB2Bs,
    required this.totalZ,
  });
}

class _PlayoffEntryTile extends StatelessWidget {
  final _PlayoffEntry entry;

  const _PlayoffEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${entry.playoffGames} games',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _gamesColor(entry.playoffGames),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Text('${entry.positions.join(",")} · ${entry.team}'),
          const SizedBox(width: 8),
          if (entry.playoffB2Bs > 0) ...[
            if (entry.playoffB2Bs > 2)
              const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orange),
            Text(
              '${entry.playoffB2Bs} B2B${entry.playoffB2Bs == 1 ? "" : "s"}',
              style: TextStyle(
                fontSize: 12,
                color: entry.playoffB2Bs > 2 ? Colors.orange[700] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            'Z ${entry.totalZ.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Color _gamesColor(int games) {
    if (games >= 15) return Colors.green[700]!;
    if (games >= 13) return Colors.teal[600]!;
    if (games >= 11) return Colors.orange[700]!;
    return Colors.red[400]!;
  }
}
