import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/positional_run_detector.dart';
import '../engine/ranking_engine.dart';
import '../engine/snake_position.dart';
import '../models/player.dart';
import '../models/ranking_result.dart';
import 'draft_state_provider.dart';
import 'league_data_provider.dart';
import 'saved_roster_provider.dart';
import 'schedule_provider.dart';
import 'settings_provider.dart';

/// Recomputes the ranked available-player list whenever the draft state
/// (any pick, any punt-toggle change), the underlying league data, the NBA
/// schedule, or the app settings change.
///
/// When schedule or settings haven't loaded yet, graceful defaults are used:
/// no playoff boost is applied (null playoffGamesByTeam) and weight defaults
/// from [AppSettings] are used.
///
/// Need-impact baseline:
/// - Draft-night mode (active draft has picks and is not complete): uses the
///   live drafted roster from the active draft.
/// - In-season mode (draft is complete or has 0 picks): uses the saved roster
///   from [savedRosterPlayersProvider] if non-empty.
final rankingsProvider = Provider<List<RankingResult>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  final draftState = ref.watch(draftStateProvider);
  final schedule = ref.watch(scheduleProvider).value; // null while loading
  final settings = ref.watch(settingsProvider);
  final savedRosterPlayers = ref.watch(savedRosterPlayersProvider);

  if (leagueData == null) return [];

  final totalPicksInDraft =
      leagueData.config.teamsCount * leagueData.config.totalRosterSize;
  final isDraftComplete = draftState.picks.length >= totalPicksInDraft;
  final isDraftEmpty = draftState.picks.isEmpty;

  final availablePool = availablePoolFrom(leagueData.players, draftState);

  // Choose the roster baseline for need-impact:
  // - Active draft (picks exist and not yet complete) → live draft roster.
  // - Otherwise (empty or complete) → saved roster if available.
  final List<Player> myRoster;
  if (!isDraftEmpty && !isDraftComplete) {
    myRoster = myRosterFrom(leagueData.players, draftState, leagueData.config.myDraftSlot);
  } else if (savedRosterPlayers.isNotEmpty) {
    myRoster = savedRosterPlayers;
  } else {
    myRoster = myRosterFrom(leagueData.players, draftState, leagueData.config.myDraftSlot);
  }

  // Compute playoff games per team for the configured window, if schedule is
  // available. Gracefully degrades to null (positional-only Need) otherwise.
  Map<String, int>? playoffGamesByTeam;
  if (schedule != null) {
    final start = DateTime.tryParse(settings.playoffStart);
    final end = DateTime.tryParse(settings.playoffEnd);
    if (start != null && end != null) {
      playoffGamesByTeam = {
        for (final entry in schedule.teams.entries)
          entry.key: entry.value.gamesInWindow(start, end),
      };
    }
  }

  return computeRankings(
    availablePool: availablePool,
    myRoster: myRoster,
    puntedCategories: draftState.puntedCategories,
    slotConfig: leagueData.config,
    playoffGamesByTeam: playoffGamesByTeam,
    scheduleBoostWeight: settings.scheduleBoostWeight,
    positionalNeedWeight: settings.positionalNeedWeight,
  );
});

final positionalRunProvider = Provider<PositionalRunWarning?>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  final draftState = ref.watch(draftStateProvider);
  if (leagueData == null) return null;
  final playersById = ref.watch(playersByIdProvider);
  return detectPositionalRun(draftState.picks, playersById);
});

final snakeWindowProvider = Provider<SnakePickWindow?>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  final draftState = ref.watch(draftStateProvider);
  if (leagueData == null) return null;
  return computeSnakeWindow(
    nextPickNumber: draftState.nextPickNumber,
    teamsCount: leagueData.config.teamsCount,
    myDraftSlot: leagueData.config.myDraftSlot,
  );
});
