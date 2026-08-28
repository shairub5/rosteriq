/// A single actionable hint from the mock-draft analyzer: at a specific pick
/// the user took [currentPlayerId], but [betterPlayerId] was still on the
/// board and would have scored [zScoreGain] more z-score points.
class SwapSuggestion {
  /// 1-based index among the user's own picks (not the global pick number).
  final int pickNumber;
  final String currentPlayerId;
  final String betterPlayerId;
  final double zScoreGain;

  const SwapSuggestion({
    required this.pickNumber,
    required this.currentPlayerId,
    required this.betterPlayerId,
    required this.zScoreGain,
  });
}
