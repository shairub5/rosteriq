import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/persistence_service.dart';

/// User-editable display names for the other teams in the draft, keyed by
/// draft slot. Falls back to "Team N" for any slot not explicitly named.
class TeamNamesNotifier extends StateNotifier<Map<int, String>> {
  final PersistenceService _persistence;

  TeamNamesNotifier(this._persistence) : super({}) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    state = await _persistence.loadTeamNames();
  }

  Future<void> setName(int teamSlot, String name) async {
    final trimmed = name.trim();
    state = {...state, if (trimmed.isNotEmpty) teamSlot: trimmed else teamSlot: ''};
    await _persistence.saveTeamNames(state);
  }
}

final teamNamesProvider = StateNotifierProvider<TeamNamesNotifier, Map<int, String>>((ref) {
  return TeamNamesNotifier(ref.watch(_persistenceServiceProvider));
});

final _persistenceServiceProvider = Provider((ref) => PersistenceService());

String displayNameForSlot(Map<int, String> teamNames, int teamSlot, int myDraftSlot) {
  if (teamSlot == myDraftSlot) return 'You';
  final name = teamNames[teamSlot];
  if (name == null || name.isEmpty) return 'Team $teamSlot';
  return name;
}
