import '../models/player.dart';
import '../models/ranking_result.dart';
import '../models/swap_suggestion.dart';
import 'snake_position.dart';

/// Strips accents and non-alphanumeric characters for accent/encoding-tolerant
/// matching. Handles `?` artifacts from Yahoo email encoding of accented chars
/// (e.g. "Joki?" → "joki" matches "Jokić" → "jokic").
String _normalizeForMatch(String s) {
  const accents = {
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y', 'ç': 'c', 'ñ': 'n',
    'ć': 'c', 'č': 'c', 'š': 's', 'ž': 'z', 'đ': 'd',
    'ā': 'a', 'ē': 'e', 'ī': 'i', 'ō': 'o', 'ū': 'u',
    'ņ': 'n', 'ģ': 'g', 'ļ': 'l', 'ķ': 'k', 'ř': 'r',
    '’': '', "'": '',
  };
  var result = s.toLowerCase();
  for (final entry in accents.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  // Strip anything remaining that isn't a-z, 0-9, space, or hyphen
  // (this also removes '?' email-encoding artifacts)
  return result.replaceAll(RegExp(r"[^a-z0-9 \-]"), '').trim();
}

/// Matches a raw name string from the mock-draft input to a [Player] in the
/// player list. Tries exact case-insensitive match first, then a contains
/// check, then an ASCII-normalized check that handles accented characters and
/// `?` encoding artifacts from Yahoo draft emails.
Player? _resolvePlayer(String name, List<Player> players) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return null;

  // 1. Exact match (case-insensitive).
  for (final p in players) {
    if (p.name.toLowerCase() == lower) return p;
  }

  // 2. Fuzzy contains.
  for (final p in players) {
    final pLower = p.name.toLowerCase();
    if (pLower.contains(lower) || lower.contains(pLower)) return p;
  }

  // 3. ASCII-normalized match — tolerates accents and '?' encoding artifacts.
  final normInput = _normalizeForMatch(name);
  if (normInput.length >= 3) {
    for (final p in players) {
      final normP = _normalizeForMatch(p.name);
      if (normP == normInput ||
          normP.contains(normInput) ||
          normInput.contains(normP)) {
        return p;
      }
    }
  }

  return null;
}

/// Identifies which global pick numbers belong to the user and analyzes each
/// of their picks to see whether a better-ranked player was still available
/// at that moment.
///
/// [allPicksInOrder] is a list of player names in global snake-draft order
/// (pick 1, 2, 3 …), covering all teams. Names that cannot be resolved to a
/// known [Player] are silently skipped - they still "consume" a draft slot
/// (i.e. they are removed from the available pool) but produce no suggestion.
///
/// Rankings are matched by [puntAdjustedZ] (the same value the live pool
/// screen ranks by). A suggestion is only emitted when the best available
/// player at that point has a strictly higher puntAdjustedZ than the player
/// the user actually took.
List<SwapSuggestion> analyzeMockDraft({
  required List<String> allPicksInOrder,
  required int myDraftSlot,
  required int teamsCount,
  required List<RankingResult> rankings,
  required List<Player> players,
}) {
  // Build lookup maps.
  final rankingByPlayerId = {for (final r in rankings) r.playerId: r};

  // Identify which global pick indices (0-based) belong to the user.
  final myGlobalPickIndices = <int>{};
  for (var i = 0; i < allPicksInOrder.length; i++) {
    final globalPickNumber = i + 1; // 1-based
    if (teamSlotForPick(globalPickNumber, teamsCount) == myDraftSlot) {
      myGlobalPickIndices.add(i);
    }
  }

  // Walk the draft in order, maintaining the still-available player set.
  final availableIds = {for (final p in players) p.id};
  final suggestions = <SwapSuggestion>[];
  var myPickNumber = 0; // 1-based counter among user's own picks

  for (var i = 0; i < allPicksInOrder.length; i++) {
    final name = allPicksInOrder[i];
    final pickedPlayer = _resolvePlayer(name, players);

    if (myGlobalPickIndices.contains(i)) {
      myPickNumber++;

      // Find the best available player by puntAdjustedZ.
      RankingResult? bestAvailableRanking;
      for (final id in availableIds) {
        final r = rankingByPlayerId[id];
        if (r == null) continue;
        if (bestAvailableRanking == null ||
            r.puntAdjustedZ > bestAvailableRanking.puntAdjustedZ) {
          bestAvailableRanking = r;
        }
      }

      if (pickedPlayer != null && bestAvailableRanking != null) {
        final myRanking = rankingByPlayerId[pickedPlayer.id];
        // Only suggest a swap if a genuinely better player was on the board.
        if (myRanking != null &&
            bestAvailableRanking.playerId != pickedPlayer.id &&
            bestAvailableRanking.puntAdjustedZ > myRanking.puntAdjustedZ) {
          suggestions.add(SwapSuggestion(
            pickNumber: myPickNumber,
            currentPlayerId: pickedPlayer.id,
            betterPlayerId: bestAvailableRanking.playerId,
            zScoreGain: bestAvailableRanking.puntAdjustedZ - myRanking.puntAdjustedZ,
          ));
        }
      }
    }

    // Remove the picked player from the available pool regardless of whether
    // we could resolve the name, so subsequent picks see the right pool.
    if (pickedPlayer != null) {
      availableIds.remove(pickedPlayer.id);
    }
  }

  return suggestions;
}
