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

/// The per-player, per-category "raw value" that gets z-scored. This is
/// where the FG%/FT% impact formula and the TO sign-inversion live - every
/// other category is just the counting stat as-is.
Map<StatCategory, double> computeRawCategoryValues(
  Player player, {
  required double poolAvgFgPct,
  required double poolAvgFtPct,
}) {
  return {
    StatCategory.fgPct: (player.fgPct - poolAvgFgPct) * player.fgAttempted,
    StatCategory.ftPct: (player.ftPct - poolAvgFtPct) * player.ftAttempted,
    StatCategory.threePM: player.threePM.toDouble(),
    StatCategory.pts: player.pts.toDouble(),
    StatCategory.reb: player.reb.toDouble(),
    StatCategory.ast: player.ast.toDouble(),
    StatCategory.stl: player.stl.toDouble(),
    StatCategory.blk: player.blk.toDouble(),
    StatCategory.to: -player.to.toDouble(),
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
