import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/draft_state.dart';
import '../models/stat_category.dart';
import '../services/persistence_service.dart';

final _persistenceServiceProvider = Provider((ref) => PersistenceService());

/// Persists the punted-category set. (Stored in the old draft-state blob, whose
/// pick log is no longer used, so existing punts survive the update.)
class DraftStateNotifier extends StateNotifier<DraftState> {
  final PersistenceService _persistence;

  DraftStateNotifier(this._persistence) : super(const DraftState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    state = await _persistence.load();
  }

  Future<void> setPuntedCategories(Set<StatCategory> categories) async {
    // At most 2 punted categories, per the league's punt-strategy design.
    state = state.withPuntedCategories(categories.take(2).toSet());
    await _persistence.save(state);
  }
}

final draftStateProvider = StateNotifierProvider<DraftStateNotifier, DraftState>((ref) {
  return DraftStateNotifier(ref.watch(_persistenceServiceProvider));
});
