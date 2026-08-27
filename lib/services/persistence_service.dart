import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/draft_state.dart';

const _draftStateKey = 'rosteriq.draft_state.v1';
const _teamNamesKey = 'rosteriq.team_names.v1';

/// Small, infrequent writes (human tap-speed during a draft, not high
/// frequency) - a single JSON blob in shared_preferences is simplest to
/// reason about and needs no schema-migration machinery, unlike Hive/sqlite.
class PersistenceService {
  Future<void> save(DraftState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftStateKey, jsonEncode(state.toJson()));
  }

  Future<DraftState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftStateKey);
    if (raw == null) return const DraftState();
    return DraftState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftStateKey);
  }

  /// Team names are keyed by draft slot (as a string, since JSON map keys
  /// must be strings) - separate from DraftState since they're set once at
  /// draft setup rather than mutated pick-by-pick.
  Future<void> saveTeamNames(Map<int, String> names) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = {for (final entry in names.entries) entry.key.toString(): entry.value};
    await prefs.setString(_teamNamesKey, jsonEncode(jsonMap));
  }

  Future<Map<int, String>> loadTeamNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_teamNamesKey);
    if (raw == null) return {};
    final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final entry in jsonMap.entries) int.parse(entry.key): entry.value as String};
  }
}
