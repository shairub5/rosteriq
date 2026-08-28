import 'dart:math' show min, max;

import '../models/draft_state.dart';
import '../models/league_config.dart';
import '../models/player.dart';
import '../models/ranking_result.dart';
import '../models/stat_category.dart';
import 'pool_stats.dart';
import 'roster_fit.dart';
import 'waiver_advisor.dart';
import 'z_score_calculator.dart';

/// The core entry point: given the current available pool, the user's own
/// roster, their punted categories, and the league's slot config, produces a
/// ranked list. Pure function, no Flutter/UI dependencies, so it's directly
/// unit-testable and reusable for the "live team standing" feature (by
/// calling it with the pool stats computed the same way, then reading off a
/// single player's/roster's z's).
///
/// Optional [playoffGamesByTeam] maps team abbreviation -> number of games in
/// the fantasy playoff window. When provided, a playoff schedule bonus (0..1,
/// normalised across the pool) is added to [needAdjustedZ], scaled by
/// [scheduleBoostWeight]. Teams not present in the map receive a neutral 0.5
/// bonus.
///
/// [positionalNeedWeight] scales the positional scarcity bonus (default 1.0
/// for backward-compatible behaviour).
List<RankingResult> computeRankings({
  required List<Player> availablePool,
  required List<Player> myRoster,
  required Set<StatCategory> puntedCategories,
  required LeagueRosterConfig slotConfig,
  Map<String, int>? playoffGamesByTeam,
  double scheduleBoostWeight = 0.5,
  double positionalNeedWeight = 1.0,
}) {
  if (availablePool.isEmpty) return [];

  final poolStats = computePoolStats(availablePool);
  final avgFg = poolAverageFgPct(availablePool);
  final avgFt = poolAverageFtPct(availablePool);
  final nonPunted = allStatCategories.where((c) => !puntedCategories.contains(c));

  // Precompute open slot types and per-slot pool counts once, not per player.
  final openTypes = openSlotTypesFor(slotConfig, myRoster);
  final poolSize = availablePool.length;
  final slotPoolCount = <String, int>{
    for (final t in openTypes.toSet())
      t: availablePool.where((p) => canFillSlotType(p, t)).length,
  };

  // Precompute team standing once for need-impact scores.
  final teamStanding = computeTeamStanding(
    myRoster: myRoster,
    fullPoolForBaseline: availablePool,
  );

  // Precompute playoff schedule bonus range once (normalise across the map).
  // Only active when at least 2 distinct game counts exist (otherwise min==max
  // and every player would get a 0/0 divide, so we treat it as inactive).
  final bool hasPlayoffData =
      playoffGamesByTeam != null && playoffGamesByTeam.length >= 2;
  final int playoffMin =
      hasPlayoffData ? playoffGamesByTeam.values.reduce(min) : 0;
  final int playoffMax =
      hasPlayoffData ? playoffGamesByTeam.values.reduce(max) : 0;
  final bool playoffRangeNonZero =
      hasPlayoffData && (playoffMax - playoffMin) > 0;

  final results = availablePool.map((player) {
    final z = computeZScores(player, poolStats, poolAvgFgPct: avgFg, poolAvgFtPct: avgFt);
    final totalZ = z.values.fold<double>(0, (sum, v) => sum + v);
    final puntAdjustedZ = nonPunted.fold<double>(0, (sum, c) => sum + z[c]!);
    final fits = hasOpenSlotFor(player, slotConfig, myRoster);

    // Positional scarcity bonus: max scarcity (0..1) across open slots this
    // player can fill. Scarcity = 1 - (eligible / poolSize).
    double positionalBonus = 0;
    if (poolSize > 0) {
      for (final t in openTypes.toSet()) {
        if (!canFillSlotType(player, t)) continue;
        final eligible = slotPoolCount[t] ?? 0;
        if (eligible > 0) {
          final scarcity = 1.0 - (eligible / poolSize);
          if (scarcity > positionalBonus) positionalBonus = scarcity;
        }
      }
    }

    // Playoff schedule bonus: 0..1 normalised game count, or neutral 0.5 when
    // the player's team is not in the map.
    double playoffBonus = 0;
    if (playoffRangeNonZero) {
      final teamGames = playoffGamesByTeam[player.team];
      if (teamGames != null) {
        playoffBonus = (teamGames - playoffMin) / (playoffMax - playoffMin);
      } else {
        playoffBonus = 0.5; // neutral for unknown teams
      }
    }

    final impact = needImpactScore(
      perCategoryZ: z,
      myTeamStanding: teamStanding,
    );

    return RankingResult(
      playerId: player.id,
      perCategoryZ: z,
      totalZ: totalZ,
      puntAdjustedZ: puntAdjustedZ,
      needAdjustedZ: puntAdjustedZ +
          (positionalNeedWeight * positionalBonus) +
          (scheduleBoostWeight * playoffBonus),
      needImpact: impact,
      rank: 0, // filled in below once sorted
      rosterFitWarning: !fits,
    );
  }).toList();

  final sortKey = puntedCategories.isEmpty
      ? (RankingResult r) => r.totalZ
      : (RankingResult r) => r.puntAdjustedZ;
  results.sort((a, b) => sortKey(b).compareTo(sortKey(a)));

  return [
    for (var i = 0; i < results.length; i++)
      RankingResult(
        playerId: results[i].playerId,
        perCategoryZ: results[i].perCategoryZ,
        totalZ: results[i].totalZ,
        puntAdjustedZ: results[i].puntAdjustedZ,
        needAdjustedZ: results[i].needAdjustedZ,
        needImpact: results[i].needImpact,
        rank: i + 1,
        rosterFitWarning: results[i].rosterFitWarning,
      ),
  ];
}

/// Reuses the exact same pool-stats/z machinery as [computeRankings] to show
/// which of the 9 categories the user's own drafted roster is currently
/// strong/weak in - intentionally the same code path, not a second
/// implementation, so "what counts as good" never drifts between the two
/// features.
Map<StatCategory, double> computeTeamStanding({
  required List<Player> myRoster,
  required List<Player> fullPoolForBaseline,
}) {
  if (myRoster.isEmpty || fullPoolForBaseline.isEmpty) {
    return {for (final c in allStatCategories) c: 0};
  }
  final poolStats = computePoolStats(fullPoolForBaseline);
  final avgFg = poolAverageFgPct(fullPoolForBaseline);
  final avgFt = poolAverageFtPct(fullPoolForBaseline);

  final perPlayerZ =
      myRoster.map((p) => computeZScores(p, poolStats, poolAvgFgPct: avgFg, poolAvgFtPct: avgFt));

  final totals = <StatCategory, double>{for (final c in allStatCategories) c: 0};
  for (final z in perPlayerZ) {
    for (final c in allStatCategories) {
      totals[c] = totals[c]! + z[c]!;
    }
  }
  return totals;
}

/// Helper for screens: resolves the set of players still on the board given
/// the full player list and the current [DraftState].
List<Player> availablePoolFrom(List<Player> allPlayers, DraftState draftState) {
  final drafted = draftState.draftedPlayerIds;
  return allPlayers.where((p) => !drafted.contains(p.id)).toList();
}

List<Player> myRosterFrom(
  List<Player> allPlayers,
  DraftState draftState,
  int myDraftSlot,
) {
  final myIds = draftState.myRosterPlayerIds(myDraftSlot).toSet();
  return allPlayers.where((p) => myIds.contains(p.id)).toList();
}
