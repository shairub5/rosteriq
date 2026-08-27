import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/positional_run_detector.dart';
import '../engine/ranking_engine.dart';
import '../engine/snake_position.dart';
import '../models/ranking_result.dart';
import 'draft_state_provider.dart';
import 'league_data_provider.dart';

/// Recomputes the ranked available-player list whenever the draft state
/// (any pick, any punt-toggle change) or the underlying league data changes.
/// This is the reactive-derivation graph the whole app's "adaptive" behavior
/// rests on - a plain Riverpod Provider, no manual listener wiring needed.
final rankingsProvider = Provider<List<RankingResult>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  final draftState = ref.watch(draftStateProvider);
  if (leagueData == null) return [];

  final availablePool = availablePoolFrom(leagueData.players, draftState);
  final myRoster = myRosterFrom(leagueData.players, draftState, leagueData.config.myDraftSlot);

  return computeRankings(
    availablePool: availablePool,
    myRoster: myRoster,
    puntedCategories: draftState.puntedCategories,
    slotConfig: leagueData.config,
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
