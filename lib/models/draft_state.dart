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
