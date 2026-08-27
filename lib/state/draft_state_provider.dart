import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/draft_state.dart';
import '../models/stat_category.dart';
import '../services/persistence_service.dart';

final _persistenceServiceProvider = Provider((ref) => PersistenceService());

/// Owns the one piece of mutable, persisted state: the full draft-board pick
/// log and the punted-category set. Every mutation re-saves to disk; writes
/// are at human tap-speed so no debouncing is needed.
class DraftStateNotifier extends StateNotifier<DraftState> {
  final PersistenceService _persistence;

  DraftStateNotifier(this._persistence) : super(const DraftState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    state = await _persistence.load();
  }

  Future<void> recordPick({required int teamSlot, required String playerId}) async {
    state = state.addPick(teamSlot: teamSlot, playerId: playerId);
    await _persistence.save(state);
  }

  Future<void> undoLastPick() async {
    state = state.undoLastPick();
    await _persistence.save(state);
  }

  Future<void> setPuntedCategories(Set<StatCategory> categories) async {
    // At most 2 punted categories, per the league's punt-strategy design.
    state = state.withPuntedCategories(categories.take(2).toSet());
    await _persistence.save(state);
  }

  Future<void> resetDraft() async {
    state = const DraftState();
    await _persistence.clear();
  }
}

final draftStateProvider = StateNotifierProvider<DraftStateNotifier, DraftState>((ref) {
  return DraftStateNotifier(ref.watch(_persistenceServiceProvider));
});
