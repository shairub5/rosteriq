import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/player.dart';
import '../models/ranking_result.dart';
import 'draft_state_provider.dart';
import 'league_data_provider.dart';
import 'league_teams_provider.dart';
import 'saved_roster_provider.dart';
import 'schedule_provider.dart';
import 'settings_provider.dart';

/// Ids of the top (teams x roster size) players by preseason rank: in a full league these are almost all rostered.
/// shortcut: a guess used only until every roster is entered; Yahoo sync replaces it.
Set<String> likelyRosteredIds(List<Player> players, int count) {
  final ranked = players.where((p) => p.sourceRank != null).toList()
    ..sort((a, b) => a.sourceRank!.compareTo(b.sourceRank!));
  return ranked.take(count).map((p) => p.id).toSet();
}

/// Free agents: everyone not on my team, not on an entered league team, not
/// marked taken, and (until every roster is entered) not a likely-rostered
/// top player.
final freeAgentsProvider = Provider<List<Player>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  final league = ref.watch(leagueTeamsProvider).value;
  final mine = (ref.watch(savedRosterProvider).value ?? const []).toSet();
  if (leagueData == null) return const [];

  final config = leagueData.config;
  final excluded = {
    ...mine,
    ...?league?.rosteredIds,
    if (!ref.watch(leagueCompleteProvider))
      ...likelyRosteredIds(leagueData.players, config.teamsCount * config.totalRosterSize),
  };
  return leagueData.players.where((p) => !excluded.contains(p.id)).toList();
});

/// Free agents ranked by z and by impact on my team's weak categories.
final rankingsProvider = Provider<List<RankingResult>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  if (leagueData == null) return [];
  final settings = ref.watch(settingsProvider);
  final schedule = ref.watch(scheduleProvider).value; // null while loading

  // Playoff games per team for the configured window, if the schedule is loaded.
  Map<String, int>? playoffGamesByTeam;
  if (schedule != null) {
    final start = DateTime.tryParse(settings.playoffStart);
    final end = DateTime.tryParse(settings.playoffEnd);
    if (start != null && end != null) {
      playoffGamesByTeam = {
        for (final entry in schedule.teams.entries) entry.key: entry.value.gamesInWindow(start, end),
      };
    }
  }

  return computeRankings(
    availablePool: ref.watch(freeAgentsProvider),
    myRoster: ref.watch(savedRosterPlayersProvider),
    puntedCategories: ref.watch(draftStateProvider).puntedCategories,
    slotConfig: leagueData.config,
    playoffGamesByTeam: playoffGamesByTeam,
    scheduleBoostWeight: settings.scheduleBoostWeight,
    positionalNeedWeight: settings.positionalNeedWeight,
  );
});

/// Punt-adjusted z of every player against the whole league pool, for showing
/// value on rostered players (mine, opponents') rather than only free agents.
final leagueZProvider = Provider<Map<String, double>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  if (leagueData == null) return const {};
  final results = computeRankings(
    availablePool: leagueData.players,
    myRoster: const [],
    puntedCategories: ref.watch(draftStateProvider).puntedCategories,
    slotConfig: leagueData.config,
  );
  final played = {for (final p in leagueData.players) if (p.gp > 0) p.id};
  // No games yet = no value to show (the UI renders "—"), rather than a misleading big negative.
  return {for (final r in results) if (played.contains(r.playerId)) r.playerId: r.puntAdjustedZ};
});
