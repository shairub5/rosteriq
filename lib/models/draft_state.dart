import 'stat_category.dart';

class DraftPick {
  final int pickNumber; // 1-indexed, overall pick number
  final int teamSlot; // 1-indexed draft slot that made this pick
  final String playerId;

  const DraftPick({
    required this.pickNumber,
    required this.teamSlot,
    required this.playerId,
  });

  factory DraftPick.fromJson(Map<String, dynamic> json) => DraftPick(
        pickNumber: json['pickNumber'] as int,
        teamSlot: json['teamSlot'] as int,
        playerId: json['playerId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'pickNumber': pickNumber,
        'teamSlot': teamSlot,
        'playerId': playerId,
      };
}

/// The one thing that's mutated live during the draft and persisted across
/// app restarts. Everything else (player pool, league config) is static,
/// bundled data.
class DraftState {
  final List<DraftPick> picks;
  final Set<StatCategory> puntedCategories;

  const DraftState({this.picks = const [], this.puntedCategories = const {}});

  int get nextPickNumber =>
      picks.isEmpty ? 1 : (picks.map((p) => p.pickNumber).reduce((a, b) => a > b ? a : b) + 1);

  Set<String> get draftedPlayerIds => picks.map((p) => p.playerId).toSet();

  List<String> myRosterPlayerIds(int myDraftSlot) =>
      picks.where((p) => p.teamSlot == myDraftSlot).map((p) => p.playerId).toList();

  DraftState addPick({required int teamSlot, required String playerId}) {
    return DraftState(
      picks: [...picks, DraftPick(pickNumber: nextPickNumber, teamSlot: teamSlot, playerId: playerId)],
      puntedCategories: puntedCategories,
    );
  }

  DraftState undoLastPick() {
    if (picks.isEmpty) return this;
    return DraftState(picks: picks.sublist(0, picks.length - 1), puntedCategories: puntedCategories);
  }

  DraftState withPuntedCategories(Set<StatCategory> newPunts) {
    return DraftState(picks: picks, puntedCategories: newPunts);
  }

  factory DraftState.fromJson(Map<String, dynamic> json) {
    return DraftState(
      picks: (json['picks'] as List? ?? [])
          .map((e) => DraftPick.fromJson(e as Map<String, dynamic>))
          .toList(),
      puntedCategories: (json['puntedCategories'] as List? ?? [])
          .map((e) => StatCategoryX.fromKey(e as String))
          .toSet(),
    );
  }

  Map<String, dynamic> toJson() => {
        'picks': picks.map((p) => p.toJson()).toList(),
        'puntedCategories': puntedCategories.map((c) => c.key).toList(),
      };
}
