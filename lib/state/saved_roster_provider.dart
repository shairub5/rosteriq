import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player.dart';
import 'league_data_provider.dart';

const _savedRosterKey = 'saved_roster_player_ids';

class SavedRosterNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedRosterKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<String>();
  }

  Future<void> saveRoster(List<String> playerIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedRosterKey, jsonEncode(playerIds));
    state = AsyncData(List<String>.from(playerIds));
  }

  Future<void> addPlayer(String playerId) async {
    final current = state.value ?? [];
    if (current.contains(playerId)) return;
    await saveRoster([...current, playerId]);
  }

  Future<void> removePlayer(String playerId) async {
    final current = state.value ?? [];
    await saveRoster(current.where((id) => id != playerId).toList());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedRosterKey);
    state = const AsyncData([]);
  }
}

final savedRosterProvider =
    AsyncNotifierProvider<SavedRosterNotifier, List<String>>(
  SavedRosterNotifier.new,
);

/// Resolves saved roster player IDs to Player objects.
/// Returns an empty list while data is loading or if no team is saved.
final savedRosterPlayersProvider = Provider<List<Player>>((ref) {
  final savedIds = ref.watch(savedRosterProvider).value ?? [];
  if (savedIds.isEmpty) return [];
  final playersById = ref.watch(playersByIdProvider);
  return savedIds
      .map((id) => playersById[id])
      .whereType<Player>()
      .toList();
});
