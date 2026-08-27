import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the available-pool list is ordered: our own live z-score ranking
/// (adaptive, recomputed as picks happen) vs. the source's original
/// pre-draft rank (static, from the Yahoo screenshots - handy as a sanity
/// check/second opinion against our calculation).
enum SortMode { ourRanking, sourceRank }

final sortModeProvider = StateProvider<SortMode>((ref) => SortMode.ourRanking);
