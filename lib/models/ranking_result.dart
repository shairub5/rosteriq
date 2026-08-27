import 'stat_category.dart';

class RankingResult {
  final String playerId;
  final Map<StatCategory, double> perCategoryZ;
  final double totalZ; // sum over all 9 categories, ignoring punts
  final double puntAdjustedZ; // sum over non-punted categories only
  final int rank; // 1-indexed, by puntAdjustedZ if punts are active else totalZ
  final bool rosterFitWarning; // true = no open roster slot currently fits this player

  const RankingResult({
    required this.playerId,
    required this.perCategoryZ,
    required this.totalZ,
    required this.puntAdjustedZ,
    required this.rank,
    required this.rosterFitWarning,
  });
}
