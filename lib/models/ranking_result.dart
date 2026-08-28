import 'stat_category.dart';

class RankingResult {
  final String playerId;
  final Map<StatCategory, double> perCategoryZ;
  final double totalZ; // sum over all 9 categories, ignoring punts
  final double puntAdjustedZ; // sum over non-punted categories only
  final double needAdjustedZ; // puntAdjustedZ + positional scarcity bonus (0..1)
  /// Waiver-wire "need impact" score: weighted sum of this player's per-cat
  /// z-scores, weighted by how weak your team is in each category. See
  /// [needImpactScore] in waiver_advisor.dart. Computed by [computeRankings]
  /// and stored here so the sort dropdown can order by it without recomputing.
  final double needImpact;
  final int rank; // 1-indexed, by puntAdjustedZ if punts are active else totalZ
  final bool rosterFitWarning; // true = no open roster slot currently fits this player

  const RankingResult({
    required this.playerId,
    required this.perCategoryZ,
    required this.totalZ,
    required this.puntAdjustedZ,
    required this.needAdjustedZ,
    this.needImpact = 0,
    required this.rank,
    required this.rosterFitWarning,
  });
}
