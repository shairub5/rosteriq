import '../models/stat_category.dart';

/// "Need Impact" score for the waiver-wire sort mode.
///
/// Weights each category's player z-score by how weak YOUR team currently is:
///   weight = max(0, -teamStanding[cat])   (negative standing = weak category)
///   needImpact = sum(playerZ[cat] * weight[cat]) / totalWeight
///
/// Returns 0 when the team has no weaknesses or the player contributes nothing.
double needImpactScore({
  required Map<StatCategory, double> perCategoryZ,
  required Map<StatCategory, double> myTeamStanding,
}) {
  double numerator = 0;
  double totalWeight = 0;

  for (final cat in allStatCategories) {
    final teamZ = myTeamStanding[cat] ?? 0;
    final weight = (-teamZ).clamp(0.0, double.infinity);
    final playerZ = perCategoryZ[cat] ?? 0;
    numerator += playerZ * weight;
    totalWeight += weight;
  }

  if (totalWeight == 0) return 0;
  return numerator / totalWeight;
}
