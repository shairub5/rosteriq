import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the available-pool list is ordered: our own live z-score ranking
/// (adaptive, recomputed as picks happen) vs. the source's original
/// pre-draft rank (static, from the Yahoo screenshots - handy as a sanity
/// check/second opinion against our calculation) vs. ADP (average draft
/// position - lower means earlier pick, so sorted ascending with nulls last)
/// vs. needImpact (how much this player fills YOUR team's weakest categories).
enum SortMode { ourRanking, sourceRank, adp, needImpact }

final sortModeProvider = StateProvider<SortMode>((ref) => SortMode.ourRanking);
