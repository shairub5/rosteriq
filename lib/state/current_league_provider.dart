import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/player_repository.dart';
import 'league_data_provider.dart';

const _key = 'selected_league';

/// The league the app is showing; persisted. 'main' = the primary league.
class SelectedLeagueNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async => (await SharedPreferences.getInstance()).getString(_key) ?? 'main';

  Future<void> select(String id) async {
    state = AsyncData(id);
    await (await SharedPreferences.getInstance()).setString(_key, id);
  }
}

final selectedLeagueIdProvider = AsyncNotifierProvider<SelectedLeagueNotifier, String>(SelectedLeagueNotifier.new);

/// The selected league's rosters and matchups (the primary one if the selection no longer exists).
final currentLeagueProvider = Provider<LeagueInfo>((ref) {
  final leagues = ref.watch(leagueDataProvider).value?.leagues ?? const [emptyMainLeague];
  final id = ref.watch(selectedLeagueIdProvider).value ?? 'main';
  return leagues.firstWhere((l) => l.id == id, orElse: () => leagues.first);
});

/// Per-league prefs key; the primary league keeps the original keys so existing data stays put.
String leagueKey(String base, String leagueId) => leagueId == 'main' ? base : '$base@$leagueId';
