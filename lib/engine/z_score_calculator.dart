import '../models/player.dart';
import '../models/stat_category.dart';
import 'pool_stats.dart';

/// Per-category z-scores for a single player against a precomputed pool
/// baseline. Kept separate from [computePoolStats] so callers that already
/// have the baseline (e.g. ranking many players in a loop) don't recompute
/// pool-wide averages per player.
Map<StatCategory, double> computeZScores(
  Player player,
  PoolStats poolStats, {
  required double poolAvgFgPct,
  required double poolAvgFtPct,
}) {
  final raw = computeRawCategoryValues(player, poolAvgFgPct: poolAvgFgPct, poolAvgFtPct: poolAvgFtPct);
  return {
    for (final category in allStatCategories)
      category: (raw[category]! - poolStats.mean[category]!) / poolStats.stdev[category]!,
  };
}
