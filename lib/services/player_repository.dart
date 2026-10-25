import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/league_config.dart';
import '../models/player.dart';
import '../worker/espn.dart';

const _snapshotUrl = 'https://raw.githubusercontent.com/shairub5/rosteriq/data/snapshot.json';

class LeagueData {
  final List<Player> players;
  final LeagueRosterConfig config;

  /// Current injuries by [Player.id]; empty when offline.
  final Map<String, InjuryEntry> injuries;

  /// When the worker last wrote the snapshot; null = offline, bundled preseason projections.
  final DateTime? updatedAt;

  /// League rosters published through the snapshot (Telegram bot today, Yahoo later), player ids re-keyed.
  final List<RemoteTeam> remoteTeams;

  const LeagueData({
    required this.players,
    required this.config,
    this.injuries = const {},
    this.updatedAt,
    this.remoteTeams = const [],
  });
}

typedef RemoteTeam = ({String name, List<String> playerIds, DateTime updatedAt});

/// Team names that mean "my own roster" when they arrive from the bot.
bool isMyTeamName(String name) => const {'my team', 'me', 'mine', 'my roster'}.contains(normalizeName(name));


/// Loads the bundled player pool + league config, then swaps in the live
/// season stats the worker publishes to the `data` branch. Falls back to the
/// bundled preseason projections if the snapshot can't be fetched or parsed.
Future<LeagueData> loadLeagueData({http.Client? client}) async {
  final playersJson = await rootBundle.loadString('assets/data/players.json');
  final configJson = await rootBundle.loadString('assets/data/league_config.json');

  final bundled = (jsonDecode(playersJson) as List)
      .map((e) => Player.fromJson(e as Map<String, dynamic>))
      .toList();
  final config = LeagueRosterConfig.fromJson(jsonDecode(configJson) as Map<String, dynamic>);

  try {
    final res = await (client ?? http.Client())
        .get(Uri.parse(_snapshotUrl))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('snapshot HTTP ${res.statusCode}');
    return mergeSnapshot(bundled, config, jsonDecode(res.body) as Map<String, dynamic>);
  } catch (_) {
    return LeagueData(players: bundled, config: config);
  }
}

/// Snapshot players use ESPN ids; saved rosters use the bundled ids. Re-key
/// by name so saved teams keep resolving, and carry over the bundled-only
/// fields (headshot id, career GP history, preseason rank) the snapshot doesn't have.
LeagueData mergeSnapshot(List<Player> bundled, LeagueRosterConfig config, Map<String, dynamic> snapshot) {
  final snapPlayers = [
    for (final j in (snapshot['players'] as List).cast<Map<String, dynamic>>())
      {...j, 'team': _espnTeams[j['team']] ?? j['team']},
  ];
  final bundledByName = {for (final p in bundled) normalizeName(p.name): p};
  final snapNames = {for (final j in snapPlayers) normalizeName(j['name'] as String)};

  // Bundled names come from screenshot OCR ("C. Bryant", "Kobe Wagler" for Keaton), so fall back to
  // first initial + surname + team, only where that key is unique on both sides and the exact name didn't match.
  Map<String, List<T>> byLooseKey<T>(Iterable<T> items, String Function(T) key) {
    final out = <String, List<T>>{};
    for (final i in items) {
      out.putIfAbsent(key(i), () => []).add(i);
    }
    return out;
  }

  final looseBundled = byLooseKey(
    bundled.where((p) => !snapNames.contains(normalizeName(p.name))),
    (p) => _looseKey(p.name, p.team),
  );
  final looseSnap = byLooseKey(snapPlayers, (j) => _looseKey(j['name'] as String, j['team'] as String));
  final idByEspnId = <String, String>{};

  final players = [
    for (final j in snapPlayers)
      () {
        final name = j['name'] as String;
        final key = _looseKey(name, j['team'] as String);
        final match = bundledByName[normalizeName(name)] ??
            (looseBundled[key]?.length == 1 && looseSnap[key]!.length == 1 ? looseBundled[key]!.single : null);
        if (match == null) return Player.fromJson(j);
        idByEspnId[j['id'] as String] = match.id;
        return Player.fromJson({
          ...j,
          'id': match.id,
          'nbaId': match.nbaId,
          'careerGpHistory': match.careerGpHistory,
          'adp': match.adp,
          'sourceRank': match.sourceRank,
        });
      }(),
  ];

  // shortcut: the snapshot only has players with stats this season, so anyone outside it (often injured, 0 GP) is
  // kept with zero season-to-date stats instead of vanishing from saved rosters; widen the worker's fetch if that hides real production.
  final matched = idByEspnId.values.toSet();
  players.addAll([
    for (final p in bundled)
      if (!matched.contains(p.id))
        Player.fromJson({
          ...p.toJson(),
          for (final k in const ['gp', 'fgPct', 'fgAttempted', 'ftPct', 'ftAttempted', 'threePM', 'pts', 'reb', 'ast', 'stl', 'blk', 'to'])
            k: 0,
          'nbaId': p.nbaId,
          'careerGpHistory': p.careerGpHistory,
        }),
  ]);

  final injuries = <String, InjuryEntry>{};
  for (final j in (snapshot['injuries'] as List).cast<Map<String, dynamic>>()) {
    final entry = InjuryEntry.fromJson(j);
    injuries[idByEspnId[entry.playerId] ?? entry.playerId] = entry;
  }

  return LeagueData(
    players: players,
    config: config,
    injuries: injuries,
    updatedAt: DateTime.parse(snapshot['updatedAt'] as String),
    remoteTeams: [
      for (final t in ((snapshot['league'] as Map?)?['teams'] as List? ?? const []).cast<Map<String, dynamic>>())
        (
          name: t['name'] as String,
          playerIds: [for (final id in (t['playerIds'] as List).cast<String>()) idByEspnId[id] ?? id],
          updatedAt: DateTime.parse(t['updatedAt'] as String),
        ),
    ],
  );
}

/// ESPN team abbreviations that differ from the bundled data's (and nba_schedule.json's).
const _espnTeams = {'GS': 'GSW', 'NO': 'NOP', 'NY': 'NYK', 'SA': 'SAS', 'UTAH': 'UTA', 'WSH': 'WAS'};

/// "Kobe Wagler" (LAC) and "Keaton Wagler" (LAC) -> "k wagler LAC".
String _looseKey(String name, String team) {
  final words = normalizeName(name).split(' ');
  final initialed = words.length < 2 ? words.join() : '${words.first[0]} ${words.skip(1).join(' ')}';
  return '$initialed $team';
}
