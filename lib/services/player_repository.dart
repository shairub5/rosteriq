import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/league_config.dart';
import '../models/player.dart';
import '../models/stat_category.dart';
import '../worker/espn.dart';

export '../worker/league_bot.dart' show isMyTeamName;

import '../worker/league_bot.dart' show extraKeys;

const _snapshotUrl = 'https://raw.githubusercontent.com/shairub5/rosteriq/data/snapshot.json';

class LeagueData {
  final List<Player> players;
  final LeagueRosterConfig config;

  /// Current injuries by [Player.id]; empty when offline.
  final Map<String, InjuryEntry> injuries;

  /// When the worker last wrote the snapshot; null = offline, bundled preseason projections.
  final DateTime? updatedAt;

  /// My fantasy leagues; the primary one (id 'main') first. Never empty.
  final List<LeagueInfo> leagues;

  /// Season minutes per game by [Player.id]; empty when offline.
  final Map<String, double> minutes;

  /// The last finished game night's box scores; null when offline or before the worker had them.
  final NightBox? lastNight;

  /// US game date -> ids of everyone who got minutes that night (this week and last). A date that's
  /// missing hasn't been fetched yet, so callers fall back to the schedule for it.
  final Map<DateTime, Set<String>> played;

  const LeagueData({
    required this.players,
    required this.config,
    this.injuries = const {},
    this.updatedAt,
    this.leagues = const [emptyMainLeague],
    this.minutes = const {},
    this.lastNight,
    this.played = const {},
  });
}

/// One game night: each player's line by [Player.id] (team codes as in the schedule), and the
/// players each team was missing to injury that night.
typedef NightBox = ({DateTime date, Map<String, NightLine> lines, Map<String, Set<String>> outByTeam});

/// "20261122" -> that date (local midnight, like the schedule's dates).
DateTime _ymdDate(String s) => DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)));

/// One fantasy league from the snapshot: rosters published through it (Telegram bot today,
/// Yahoo later) and every matchup entered with both teams' real weekly totals, sorted by week.
typedef LeagueInfo = ({
  String id,
  String name,
  /// My team's name as it appears in matchups (learned by the bot); null until known.
  String? myName,
  List<RemoteTeam> remoteTeams,
  List<LeagueMatchup> matchups,
});

const LeagueInfo emptyMainLeague = (id: 'main', name: 'My league', myName: null, remoteTeams: [], matchups: []);

/// One team's week: the 9 category totals, plus `extra` = fgm/fga/ftm/fta/gp/remaining when the
/// screenshot showed them (used for the projected final).
typedef TeamWeek = ({String name, Map<StatCategory, double> stats, Map<String, double> extra});
typedef LeagueMatchup = ({int week, TeamWeek a, TeamWeek b, DateTime updatedAt});

typedef RemoteTeam = ({String name, List<String> playerIds, DateTime updatedAt});



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
      {...j, 'team': espnTeams[j['team']] ?? j['team']},
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

  // Injured players with no games yet are only in the injury report (ESPN id). Map them to the bundled
  // player by name too, or add them, so rosters and injury badges point at one player, not two copies.
  final snapIds = {for (final j in snapPlayers) j['id'] as String};
  // Bundled players that got live stats; everyone else (incl. injury-only matches below) keeps a zero-stat copy.
  final statsMatched = idByEspnId.values.toSet();
  final zero = const ['gp', 'fgPct', 'fgAttempted', 'ftPct', 'ftAttempted', 'threePM', 'pts', 'reb', 'ast', 'stl', 'blk', 'to'];
  final injuryEntries = [
    for (final j in (snapshot['injuries'] as List).cast<Map<String, dynamic>>()) InjuryEntry.fromJson(j),
  ];
  for (final i in injuryEntries) {
    if (snapIds.contains(i.playerId) || idByEspnId.containsKey(i.playerId)) continue;
    final team = espnTeams[i.team] ?? i.team;
    final loose = looseBundled[_looseKey(i.name, team)];
    final match = bundledByName[normalizeName(i.name)] ?? (loose?.length == 1 ? loose!.single : null);
    if (match != null) {
      idByEspnId[i.playerId] = match.id;
    } else {
      players.add(Player.fromJson({
        'id': i.playerId,
        'name': i.name,
        'team': team,
        'eligiblePositions': espnPositions(i.position),
        for (final k in zero) k: 0,
      }));
    }
  }

  // shortcut: the snapshot only has players with stats this season, so anyone outside it (often injured, 0 GP) is
  // kept with zero season-to-date stats instead of vanishing from saved rosters; widen the worker's fetch if that hides real production.
  players.addAll([
    for (final p in bundled)
      if (!statsMatched.contains(p.id))
        Player.fromJson({
          ...p.toJson(),
          for (final k in zero) k: 0,
          'nbaId': p.nbaId,
          'careerGpHistory': p.careerGpHistory,
        }),
  ]);

  final injuries = {for (final i in injuryEntries) idByEspnId[i.playerId] ?? i.playerId: i};
  String appId(String espnId) => idByEspnId[espnId] ?? espnId;
  final night = snapshot['lastNight'] as Map<String, dynamic>?;

  return LeagueData(
    players: players,
    config: config,
    injuries: injuries,
    updatedAt: DateTime.parse(snapshot['updatedAt'] as String),
    minutes: {
      for (final j in snapPlayers)
        if (j['minutes'] case final num m) appId(j['id'] as String): m.toDouble(),
    },
    lastNight: night == null
        ? null
        : (
            date: _ymdDate(night['date'] as String),
            lines: {
              for (final j in (night['players'] as List).cast<Map<String, dynamic>>())
                appId(j['id'] as String): (
                  id: appId(j['id'] as String),
                  name: j['name'] as String,
                  team: espnTeams[j['team']] ?? j['team'] as String,
                  min: (j['min'] as num).toDouble(),
                  pts: j['pts'] as int,
                  reb: j['reb'] as int,
                  ast: j['ast'] as int,
                  threePM: j['threePM'] as int,
                  stl: j['stl'] as int,
                  blk: j['blk'] as int,
                  to: j['to'] as int,
                  fgm: j['fgm'] as int,
                  fga: j['fga'] as int,
                  ftm: j['ftm'] as int,
                  fta: j['fta'] as int,
                ),
            },
            outByTeam: {
              for (final e in ((night['outByTeam'] as Map?) ?? const {}).entries)
                espnTeams[e.key] ?? e.key as String: {for (final id in (e.value as List).cast<String>()) appId(id)},
            },
          ),
    played: {
      for (final e in ((snapshot['played'] as Map?) ?? const {}).entries)
        _ymdDate(e.key as String): {for (final id in ((e.value as Map)['ids'] as List).cast<String>()) appId(id)},
    },
    leagues: [
      for (final (i, l) in [
        (snapshot['league'] as Map?) ?? const {},
        ...((snapshot['leagues'] as List?) ?? const []).cast<Map>(),
      ].indexed)
        (
          id: i == 0 ? 'main' : (l['id'] as String? ?? 'league$i'),
          name: l['name'] as String? ?? (i == 0 ? 'My league' : 'League ${i + 1}'),
          myName: l['myName'] as String?,
          remoteTeams: [
            for (final t in ((l['teams'] as List?) ?? const []).cast<Map<String, dynamic>>())
              (
                name: t['name'] as String,
                playerIds: [for (final id in (t['playerIds'] as List).cast<String>()) idByEspnId[id] ?? id],
                updatedAt: DateTime.parse(t['updatedAt'] as String),
              ),
          ],
          matchups: [
            for (final m in ((l['matchups'] as List?) ?? const []).cast<Map<String, dynamic>>())
              if ((m['teams'] as List?)?.length == 2)
                () {
                  TeamWeek side(Map t) => (
                        name: t['name'] as String,
                        // A missing category (week not started) counts as 0 instead of failing the whole load.
                        stats: {for (final c in allStatCategories) c: ((t['stats'] as Map)[c.name] as num? ?? 0).toDouble()},
                        extra: {
                          for (final k in extraKeys)
                            if ((t['stats'] as Map)[k] case final num v) k: v.toDouble(),
                        },
                      );
                  final t = (m['teams'] as List).cast<Map>();
                  return (
                    week: m['week'] as int,
                    a: side(t[0]),
                    b: side(t[1]),
                    updatedAt: DateTime.parse(m['updatedAt'] as String),
                  );
                }(),
          ],
        ),
    ],
  );
}


/// "Kobe Wagler" (LAC) and "Keaton Wagler" (LAC) -> "k wagler LAC".
String _looseKey(String name, String team) {
  final words = normalizeName(name).split(' ');
  final initialed = words.length < 2 ? words.join() : '${words.first[0]} ${words.skip(1).join(' ')}';
  return '$initialed $team';
}
