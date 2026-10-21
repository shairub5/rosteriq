import 'dart:math';

import '../models/player.dart';
import '../models/stat_category.dart';

class _MeanStdev {
  final double mean;
  final double stdev;
  const _MeanStdev(this.mean, this.stdev);
}

_MeanStdev _meanStdev(List<double> values) {
  if (values.isEmpty) return const _MeanStdev(0, 1);
  final mean = values.reduce((a, b) => a + b) / values.length;
  if (values.length == 1) return _MeanStdev(mean, 1);
  final variance =
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
  final stdev = sqrt(variance);
  // Guard against a degenerate all-equal category collapsing every z to
  // +/-infinity - treat it as "no signal" instead.
  return _MeanStdev(mean, stdev == 0 ? 1 : stdev);
}

/// Per-category baseline (mean/stdev of the "raw value" fed into z-scoring)
/// computed over the CURRENT available pool. For FG%/FT% the "raw value" is
/// the attempts-weighted impact score, not the percentage itself - see
/// [computeRawCategoryValues].
class PoolStats {
  final Map<StatCategory, double> mean;
  final Map<StatCategory, double> stdev;

  const PoolStats({required this.mean, required this.stdev});
}

/// Attempts-weighted pool-average percentage: sum(makes)/sum(attempts), not
/// a naive average of per-player percentages. Falls back to a simple average
/// if no player in the pool has attempts data yet (e.g. before the
/// prior-season merge has run).
double poolAverageFgPct(List<Player> pool) {
  final totalAttempts = pool.fold<int>(0, (sum, p) => sum + p.fgAttempted);
  if (totalAttempts == 0) {
    if (pool.isEmpty) return 0;
    return pool.map((p) => p.fgPct).reduce((a, b) => a + b) / pool.length;
  }
  final totalMade = pool.fold<double>(0, (sum, p) => sum + p.fgPct * p.fgAttempted);
  return totalMade / totalAttempts;
}

double poolAverageFtPct(List<Player> pool) {
  final totalAttempts = pool.fold<int>(0, (sum, p) => sum + p.ftAttempted);
  if (totalAttempts == 0) {
    if (pool.isEmpty) return 0;
    return pool.map((p) => p.ftPct).reduce((a, b) => a + b) / pool.length;
  }
  final totalMade = pool.fold<double>(0, (sum, p) => sum + p.ftPct * p.ftAttempted);
  return totalMade / totalAttempts;
}

/// Blends this season's projected games with real recent-season history and
/// applies an extra discount for a pattern of missed time, so a player whose
/// projection assumes full health but who has actually missed significant
/// time in multiple recent seasons doesn't get credited as if that risk
/// weren't there. Players with no history (rookies, unmatched) are
/// unaffected - we only discount when we have real data.
double durabilityAdjustedGp(Player player) {
  final history = player.careerGpHistory;
  if (history == null || history.isEmpty) return player.gp.toDouble();

  final avgCareerGp = history.reduce((a, b) => a + b) / history.length;
  final blended = 0.5 * player.gp + 0.5 * avgCareerGp;

  // A season under ~65 GP (missed 17+ of 82) counts as a significant-injury
  // season; two or more in the lookback window compounds the discount.
  final injurySeasons = history.where((gp) => gp < 65).length;
  final penalty = injurySeasons >= 2 ? 0.90 : (injurySeasons == 1 ? 0.95 : 1.0);

  return (blended * penalty).clamp(1.0, 82.0);
}

/// The per-player, per-category "raw value" that gets z-scored. This is
/// where the FG%/FT% impact formula and the TO sign-inversion live - every
/// other category is just the counting stat as-is.
Map<StatCategory, double> computeRawCategoryValues(
  Player player, {
  required double poolAvgFgPct,
  required double poolAvgFtPct,
}) {
  final gp = player.gp > 0 ? player.gp.toDouble() : 1.0;
  // Discounts the per-game rate down toward the durability-adjusted games
  // expectation when real history says the projection is optimistic; never
  // boosts it. Per-game ability (the rate itself) is untouched.
  final durabilityMultiplier = (durabilityAdjustedGp(player) / gp).clamp(0.0, 1.0);
  return {
    StatCategory.fgPct: (player.fgPct - poolAvgFgPct) * (player.fgAttempted / gp) * durabilityMultiplier,
    StatCategory.ftPct: (player.ftPct - poolAvgFtPct) * (player.ftAttempted / gp) * durabilityMultiplier,
    StatCategory.threePM: player.threePM / gp * durabilityMultiplier,
    StatCategory.pts: player.pts / gp * durabilityMultiplier,
    StatCategory.reb: player.reb / gp * durabilityMultiplier,
    StatCategory.ast: player.ast / gp * durabilityMultiplier,
    StatCategory.stl: player.stl / gp * durabilityMultiplier,
    StatCategory.blk: player.blk / gp * durabilityMultiplier,
    StatCategory.to: -player.to / gp * durabilityMultiplier,
  };
}

/// Recomputes mean/stdev per category over [pool]. Call this every time the
/// available pool changes (a pick happens) - this is what makes the ranking
/// adaptive rather than a static pre-draft sheet.
PoolStats computePoolStats(List<Player> pool) {
  if (pool.isEmpty) {
    return PoolStats(
      mean: {for (final c in allStatCategories) c: 0},
      stdev: {for (final c in allStatCategories) c: 1},
    );
  }

  final avgFg = poolAverageFgPct(pool);
  final avgFt = poolAverageFtPct(pool);

  final rawByPlayer = pool
      .map((p) => computeRawCategoryValues(p, poolAvgFgPct: avgFg, poolAvgFtPct: avgFt))
      .toList();

  final mean = <StatCategory, double>{};
  final stdev = <StatCategory, double>{};
  for (final category in allStatCategories) {
    final values = rawByPlayer.map((m) => m[category]!).toList();
    final ms = _meanStdev(values);
    mean[category] = ms.mean;
    stdev[category] = ms.stdev;
  }
  return PoolStats(mean: mean, stdev: stdev);
}
