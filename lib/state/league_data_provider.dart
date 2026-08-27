import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player.dart';
import '../services/player_repository.dart';

final leagueDataProvider = FutureProvider<LeagueData>((ref) => loadLeagueData());

/// Convenience lookup by id, derived from the loaded player list.
final playersByIdProvider = Provider<Map<String, Player>>((ref) {
  final leagueData = ref.watch(leagueDataProvider).value;
  if (leagueData == null) return {};
  return {for (final p in leagueData.players) p.id: p};
});
