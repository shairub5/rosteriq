import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/draft_state_provider.dart';
import '../state/league_data_provider.dart';
import '../state/ranking_provider.dart';
import '../state/sort_mode_provider.dart';
import '../state/stats_view_mode_provider.dart';
import '../state/team_names_provider.dart';
import '../widgets/player_tile.dart';
import '../widgets/positional_run_banner.dart';
import '../widgets/snake_pick_indicator.dart';
import 'punt_settings_sheet.dart';

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
        final teamNames = ref.watch(teamNamesProvider);
        final sortMode = ref.watch(sortModeProvider);

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
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Available Pool'),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Punt settings',
                onPressed: () => showPuntSettingsSheet(context, ref),
              ),
            ],
          ),
          body: Column(
            children: [
              if (snakeWindow != null) SnakePickIndicator(window: snakeWindow),
              if (positionalRun != null) PositionalRunBanner(warning: positionalRun),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<SortMode>(
                        initialValue: sortMode,
                        decoration: const InputDecoration(
                          labelText: 'Sort',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: SortMode.ourRanking, child: Text('Our Ranking')),
                          DropdownMenuItem(value: SortMode.sourceRank, child: Text('Source Rank')),
                        ],
                        onChanged: (value) {
                          if (value != null) ref.read(sortModeProvider.notifier).state = value;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<StatsViewMode>(
                        initialValue: statsViewMode,
                        decoration: const InputDecoration(
                          labelText: 'Stats',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: StatsViewMode.projected, child: Text('Projected')),
                          DropdownMenuItem(value: StatsViewMode.lastYear, child: Text('Last Year')),
                        ],
                        onChanged: (value) {
                          if (value != null) ref.read(statsViewModeProvider.notifier).state = value;
                        },
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
                    return PlayerTile(
                      player: player,
                      ranking: ranking,
                      showPuntAdjusted: puntedCategories.isNotEmpty,
                      displayStats: displayStats,
                      teamsCount: leagueData.config.teamsCount,
                      myDraftSlot: leagueData.config.myDraftSlot,
                      teamNames: teamNames,
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
