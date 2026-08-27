import '../models/draft_state.dart';
import '../models/player.dart';

class PositionalRunWarning {
  final String position;
  final int countInWindow;
  final int windowSize;

  const PositionalRunWarning({
    required this.position,
    required this.countInWindow,
    required this.windowSize,
  });

  String get message => '$countInWindow of the last $windowSize picks were $position';
}

/// Simple heuristic, expected to need tuning after the mock-draft dry run:
/// look at the last [windowSize] picks (across every team, not just yours)
/// and flag a position if it accounts for at least [threshold] of them.
/// Uses each player's primary (first-listed) eligible position, so a
/// multi-position player only counts once, toward their most natural slot.
PositionalRunWarning? detectPositionalRun(
  List<DraftPick> picks,
  Map<String, Player> playersById, {
  int windowSize = 6,
  int threshold = 4,
}) {
  if (picks.isEmpty) return null;
  final recent = picks.length <= windowSize ? picks : picks.sublist(picks.length - windowSize);
  final effectiveWindow = recent.length;

  final counts = <String, int>{};
  for (final pick in recent) {
    final player = playersById[pick.playerId];
    if (player == null || player.eligiblePositions.isEmpty) continue;
    final primary = player.eligiblePositions.first;
    counts[primary] = (counts[primary] ?? 0) + 1;
  }

  String? runPosition;
  var runCount = 0;
  counts.forEach((position, count) {
    if (count >= threshold && count > runCount) {
      runPosition = position;
      runCount = count;
    }
  });

  if (runPosition == null) return null;
  return PositionalRunWarning(
    position: runPosition!,
    countInWindow: runCount,
    windowSize: effectiveWindow,
  );
}
