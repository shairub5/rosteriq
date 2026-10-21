import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/schedule_service.dart';
import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import '../state/saved_roster_provider.dart';
import '../state/schedule_provider.dart';
import '../state/settings_provider.dart';
import '../state/sort_mode_provider.dart';
import '../state/stats_display_mode_provider.dart';
import '../state/stats_view_mode_provider.dart';
import '../state/team_names_provider.dart';
import '../widgets/player_tile.dart';
import '../widgets/positional_run_banner.dart';
import '../widgets/snake_pick_indicator.dart';
import 'punt_settings_sheet.dart';
import 'settings_screen.dart';

class AvailablePoolScreen extends ConsumerWidget {
  const AvailablePoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagueDataAsync = ref.watch(leagueDataProvider);

    return leagueDataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, st) => Center(child: Text('Failed to load player data: $err')),
      data: (leagueData) {
        final rankings = ref.watch(rankingsProvider);
        final playersById = ref.watch(playersByIdProvider);
        final draftState = ref.watch(draftStateProvider);
        final snakeWindow = ref.watch(snakeWindowProvider);
        final positionalRun = ref.watch(positionalRunProvider);
        final puntedCategories = draftState.puntedCategories;
        final statsViewMode = ref.watch(statsViewModeProvider);
        final statsDisplayMode = ref.watch(statsDisplayModeProvider);
        final teamNames = ref.watch(teamNamesProvider);
        final sortMode = ref.watch(sortModeProvider);
        final settings = ref.watch(settingsProvider);
        final savedRosterPlayers = ref.watch(savedRosterPlayersProvider);
        final showSavedTeamBanner =
            savedRosterPlayers.isNotEmpty && draftState.picks.isEmpty;

        // Schedule is optional — if not yet loaded we skip badges gracefully.
        final schedule = ref.watch(scheduleProvider).value;
        final today = DateTime.now();

        final displayedRankings = [...rankings];
        if (sortMode == SortMode.sourceRank) {
          displayedRankings.sort((a, b) {
            final aRank = playersById[a.playerId]?.sourceRank;
            final bRank = playersById[b.playerId]?.sourceRank;
            if (aRank == null && bRank == null) return 0;
            if (aRank == null) return 1;
            if (bRank == null) return -1;
            return aRank.compareTo(bRank);
          });
        } else if (sortMode == SortMode.adp) {
          displayedRankings.sort((a, b) {
            final aAdp = playersById[a.playerId]?.adp;
            final bAdp = playersById[b.playerId]?.adp;
            if (aAdp == null && bAdp == null) return 0;
            if (aAdp == null) return 1;
            if (bAdp == null) return -1;
            return aAdp.compareTo(bAdp);
          });
        } else if (sortMode == SortMode.needImpact) {
          displayedRankings.sort((a, b) => b.needImpact.compareTo(a.needImpact));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Available Pool'),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter & Sort',
                onPressed: () => showPuntSettingsSheet(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (snakeWindow != null) SnakePickIndicator(window: snakeWindow),
              if (positionalRun != null) PositionalRunBanner(warning: positionalRun),
              if (showSavedTeamBanner)
                Container(
                  color: Colors.teal.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.teal.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Showing Need Impact vs. your saved team',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.teal.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              // Column headers
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 4, 12, 2),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    SizedBox(
                      width: 42,
                      child: Text(
                        'Z',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600], letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Need',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal[700], letterSpacing: 0.5),
                          ),
                          if (settings.scheduleBoostWeight > 0)
                            Text(
                              'pos+sched',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 8, color: Colors.teal[400], letterSpacing: 0.2),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: displayedRankings.length,
                  itemBuilder: (context, index) {
                    final ranking = displayedRankings[index];
                    final player = playersById[ranking.playerId];
                    if (player == null) return const SizedBox.shrink();
                    final displayStats = statsViewMode == StatsViewMode.lastYear
                        ? (player.priorSeason ?? player.projectedStatLine)
                        : player.projectedStatLine;

                    // Schedule-based badges: null when schedule not yet loaded.
                    final teamSched = schedule?.teams[player.team];
                    final gamesThisWeek = teamSched?.gamesThisWeek(today);
                    final hasB2B = _isBackToBackStartingToday(teamSched, today);

                    return PlayerTile(
                      player: player,
                      ranking: ranking,
                      showPuntAdjusted: puntedCategories.isNotEmpty,
                      showAdp: sortMode == SortMode.adp,
                      displayStats: displayStats,
                      statsDisplayMode: statsDisplayMode,
                      teamsCount: leagueData.config.teamsCount,
                      myDraftSlot: leagueData.config.myDraftSlot,
                      teamNames: teamNames,
                      gamesThisWeek: gamesThisWeek,
                      hasBackToBack: hasB2B,
                      onDraftedByMe: () => ref.read(draftStateProvider.notifier).recordPick(
                            teamSlot: leagueData.config.myDraftSlot,
                            playerId: player.id,
                          ),
                      onDraftedByOther: (teamSlot) => ref.read(draftStateProvider.notifier).recordPick(
                            teamSlot: teamSlot,
                            playerId: player.id,
                          ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Returns true when [teamSched] has a game today AND the game tomorrow is
/// in the back-to-back set (i.e. tonight starts a back-to-back stretch).
bool _isBackToBackStartingToday(TeamSchedule? teamSched, DateTime today) {
  if (teamSched == null) return false;
  if (!teamSched.hasGameOn(today)) return false;
  final tomorrow = today.add(const Duration(days: 1));
  return teamSched.hasBackToBackOn(tomorrow);
}
