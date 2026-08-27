class RosterSlot {
  final String type; // e.g. "PG", "G", "F", "UTIL", "BN"
  final int count;

  const RosterSlot({required this.type, required this.count});

  factory RosterSlot.fromJson(Map<String, dynamic> json) =>
      RosterSlot(type: json['type'] as String, count: json['count'] as int);

  Map<String, dynamic> toJson() => {'type': type, 'count': count};
}

/// Maps a flex slot type to the eligible-position values that can fill it.
/// Dedicated slots (PG, SG, SF, PF, C) match the position literally.
const Map<String, List<String>> flexSlotEligibility = {
  'G': ['PG', 'SG'],
  'F': ['SF', 'PF'],
  'UTIL': ['PG', 'SG', 'SF', 'PF', 'C'],
  'BN': ['PG', 'SG', 'SF', 'PF', 'C'],
};

class LeagueRosterConfig {
  final int teamsCount;
  final int myDraftSlot; // 1-indexed
  final List<RosterSlot> rosterSlots;

  const LeagueRosterConfig({
    required this.teamsCount,
    required this.myDraftSlot,
    required this.rosterSlots,
  });

  int get totalRosterSize => rosterSlots.fold(0, (sum, s) => sum + s.count);

  factory LeagueRosterConfig.fromJson(Map<String, dynamic> json) {
    return LeagueRosterConfig(
      teamsCount: json['teamsCount'] as int,
      myDraftSlot: json['myDraftSlot'] as int,
      rosterSlots: (json['rosterSlots'] as List)
          .map((e) => RosterSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'teamsCount': teamsCount,
        'myDraftSlot': myDraftSlot,
        'rosterSlots': rosterSlots.map((s) => s.toJson()).toList(),
      };

  static const defaultConfig = LeagueRosterConfig(
    teamsCount: 12,
    myDraftSlot: 12,
    rosterSlots: [
      RosterSlot(type: 'PG', count: 1),
      RosterSlot(type: 'SG', count: 1),
      RosterSlot(type: 'SF', count: 1),
      RosterSlot(type: 'PF', count: 1),
      RosterSlot(type: 'C', count: 1),
      RosterSlot(type: 'G', count: 1),
      RosterSlot(type: 'F', count: 1),
      RosterSlot(type: 'UTIL', count: 3),
      RosterSlot(type: 'BN', count: 3),
    ],
  );
}
