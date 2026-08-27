import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ranking_engine.dart';
import '../models/stat_category.dart';
import 'draft_state_provider.dart';
import 'league_data_provider.dart';

/// Which of the 9 categories the user's own drafted roster is currently
/// strong/weak in, reusing the same z-score baseline as the rankings - see
/// [computeTeamStanding].
final teamStandingProvider = Provider<Map<StatCategory, double>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  final draftState = ref.watch(draftStateProvider);
  if (leagueData == null) {
    return {for (final c in allStatCategories) c: 0};
  }
  final myRoster = myRosterFrom(leagueData.players, draftState, leagueData.config.myDraftSlot);
  return computeTeamStanding(myRoster: myRoster, fullPoolForBaseline: leagueData.players);
});
