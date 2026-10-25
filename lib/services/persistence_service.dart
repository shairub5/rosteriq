import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/draft_state.dart';

const _draftStateKey = 'rosteriq.draft_state.v1';

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
}
