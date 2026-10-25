import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/player_repository.dart';
import '../worker/espn.dart' show normalizeName;
import 'league_data_provider.dart';
import 'saved_roster_provider.dart';

const _key = 'league_teams_v1';
const _otherTeamsCount = 11;

class LeagueTeam {
  final String id;
  final String name;
  final List<String> playerIds;

  const LeagueTeam({required this.id, required this.name, this.playerIds = const []});

  LeagueTeam copyWith({String? name, List<String>? playerIds}) =>
      LeagueTeam(id: id, name: name ?? this.name, playerIds: playerIds ?? this.playerIds);

  factory LeagueTeam.fromJson(Map<String, dynamic> j) => LeagueTeam(
        id: j['id'] as String,
        name: j['name'] as String,
        playerIds: (j['playerIds'] as List).cast<String>(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'playerIds': playerIds};
}

/// The other 11 teams in the league, entered by hand until Yahoo sync, plus
/// players known to be rostered somewhere unknown ("taken"). My own team stays
/// in [savedRosterProvider].
class LeagueState {
  final List<LeagueTeam> teams;
  final Set<String> takenIds;

  /// Remote team name (normalized) -> updatedAt of the version already applied, so a
  /// remote roster overwrites local edits only when it's newer.
  final Map<String, String> remoteApplied;

  const LeagueState({required this.teams, this.takenIds = const {}, this.remoteApplied = const {}});


  /// Everyone on another team or marked taken.
  Set<String> get rosteredIds => {for (final t in teams) ...t.playerIds, ...takenIds};

  LeagueTeam? teamOf(String playerId) => teams.where((t) => t.playerIds.contains(playerId)).firstOrNull;

  LeagueState copyWith({
    List<LeagueTeam>? teams,
    Set<String>? takenIds,
    Map<String, String>? remoteApplied,
  }) =>
      LeagueState(
        teams: teams ?? this.teams,
        takenIds: takenIds ?? this.takenIds,
        remoteApplied: remoteApplied ?? this.remoteApplied,
      );

  Map<String, dynamic> toJson() => {
        'teams': teams.map((t) => t.toJson()).toList(),
        'takenIds': takenIds.toList(),
        'remoteApplied': remoteApplied,
      };

  /// Applies one remote roster: replaces the team with the same name, or takes over a
  /// "Team N" slot. The players leave any other team and the taken list. Null when every
  /// team already has a real name.
  LeagueState? withRemoteTeam(RemoteTeam r) {
    final key = normalizeName(r.name);
    // Same name, else an unnamed "Team N" slot (an empty one first, so hand-entered rosters survive).
    final unnamed = teams.where((t) => RegExp(r'^Team \d+$').hasMatch(t.name));
    final target = teams.where((t) => normalizeName(t.name) == key).firstOrNull ??
        unnamed.where((t) => t.playerIds.isEmpty).firstOrNull ??
        unnamed.firstOrNull;
    if (target == null) return null;
    final ids = r.playerIds.toSet();
    return copyWith(
      teams: [
        for (final t in teams)
          t.id == target.id
              ? t.copyWith(name: r.name, playerIds: r.playerIds)
              : t.copyWith(playerIds: t.playerIds.where((id) => !ids.contains(id)).toList()),
      ],
      takenIds: takenIds.difference(ids),
      remoteApplied: {...remoteApplied, key: r.updatedAt.toIso8601String()},
    );
  }
}

class LeagueTeamsNotifier extends AsyncNotifier<LeagueState> {
  @override
  Future<LeagueState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    var league = raw == null ? _fresh(prefs) : _parse(raw);

    // Pull in rosters sent through the bot (or Yahoo later) that are newer than what was applied.
    final remote = (await ref.watch(leagueDataProvider.future)).remoteTeams;
    var changed = false;
    for (final r in remote) {
      final key = normalizeName(r.name);
      final applied = DateTime.tryParse(league.remoteApplied[key] ?? '');
      if (applied != null && !r.updatedAt.isAfter(applied)) continue;
      if (isMyTeamName(r.name)) {
        await ref.read(savedRosterProvider.notifier).saveRoster(r.playerIds);
        final ids = r.playerIds.toSet();
        league = league.copyWith(
          teams: [for (final t in league.teams) t.copyWith(playerIds: t.playerIds.where((id) => !ids.contains(id)).toList())],
          takenIds: league.takenIds.difference(ids),
          remoteApplied: {...league.remoteApplied, key: r.updatedAt.toIso8601String()},
        );
      } else {
        league = league.withRemoteTeam(r) ?? league;
      }
      changed = true;
    }
    if (changed) await prefs.setString(_key, jsonEncode(league.toJson()));
    return league;
  }

  LeagueState _parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return LeagueState(
      teams: (j['teams'] as List).map((t) => LeagueTeam.fromJson(t as Map<String, dynamic>)).toList(),
      takenIds: (j['takenIds'] as List).cast<String>().toSet(),
      remoteApplied: ((j['remoteApplied'] as Map?) ?? const {}).cast<String, String>(),
    );
  }

  LeagueState _fresh(SharedPreferences prefs) {
    // First run: blank teams. Carries over a hand-picked opponent from the earlier Matchup build.
    final oldRaw = prefs.getString('opponent_roster_player_ids');
    final oldOpponent = oldRaw == null ? null : (jsonDecode(oldRaw) as List).cast<String>();
    return LeagueState(
      teams: [
        for (var i = 1; i <= _otherTeamsCount; i++)
          LeagueTeam(id: 't$i', name: 'Team $i', playerIds: i == 1 ? oldOpponent ?? const [] : const []),
      ],
    );
  }

  Future<void> _save(LeagueState next) async {
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }

  LeagueState get _s => state.requireValue;

  Future<void> rename(String teamId, String name) => _save(_s.copyWith(teams: [
        for (final t in _s.teams) t.id == teamId ? t.copyWith(name: name.trim().isEmpty ? t.name : name.trim()) : t,
      ]));

  /// Adds [playerId] to [teamId] (moving it off any other team / the taken list), or removes it if already there.
  Future<void> togglePlayer(String teamId, String playerId) {
    final onTeam = _s.teams.firstWhere((t) => t.id == teamId).playerIds.contains(playerId);
    return _save(_s.copyWith(
      teams: [
        for (final t in _s.teams)
          t.copyWith(playerIds: [
            ...t.playerIds.where((id) => id != playerId),
            if (t.id == teamId && !onTeam) playerId,
          ]),
      ],
      takenIds: {..._s.takenIds}..remove(playerId),
    ));
  }

  Future<void> markTaken(String playerId) => _save(_s.copyWith(takenIds: {..._s.takenIds, playerId}));

  Future<void> clearTaken() => _save(_s.copyWith(takenIds: {}));
}

final leagueTeamsProvider = AsyncNotifierProvider<LeagueTeamsNotifier, LeagueState>(LeagueTeamsNotifier.new);

/// True once every team (mine + the other 11) has a full roster, so free agents no longer need guessing.
final leagueCompleteProvider = Provider<bool>((ref) {
  final config = ref.watch(leagueDataProvider).value?.config;
  final league = ref.watch(leagueTeamsProvider).value;
  final mine = ref.watch(savedRosterProvider).value ?? const [];
  if (config == null || league == null) return false;
  final size = config.totalRosterSize;
  return mine.length >= size && league.teams.every((t) => t.playerIds.length >= size);
});
