import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/player.dart';

/// ESPN's public NBA endpoints - no login, work from cloud IPs (unlike
/// stats.nba.com / cdn.nba.com, which 403). Undocumented, so parsing is
/// covered by test/worker_test.dart fixtures.
const _statsUrl =
    'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/statistics/byathlete'
    '?region=us&lang=en&contentorigin=espn&isqualified=false&limit=200'
    '&sort=offensive.avgPoints:desc&seasontype=2';
const _injuriesUrl = 'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/injuries';

class InjuryEntry {
  final String playerId; // ESPN athlete id, same as Player.id from [parseStatsPage]
  final String name;
  final String team;
  final String position; // ESPN abbreviation: G, F, C
  final String status; // "Out", "Day-To-Day"
  final String detail; // e.g. "Foot Fracture"
  final String? returnDate;

  const InjuryEntry({
    required this.playerId,
    required this.name,
    required this.team,
    required this.position,
    required this.status,
    required this.detail,
    this.returnDate,
  });

  factory InjuryEntry.fromJson(Map<String, dynamic> json) => InjuryEntry(
        playerId: json['playerId'] as String,
        name: json['name'] as String,
        team: json['team'] as String,
        position: json['position'] as String,
        status: json['status'] as String,
        detail: json['detail'] as String,
        returnDate: json['returnDate'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'name': name,
        'team': team,
        'position': position,
        'status': status,
        'detail': detail,
        'returnDate': returnDate,
      };
}

/// ESPN only gives G / F / C (occasionally G-F); map onto the app's slot positions.
List<String> espnPositions(String abbr) => [
      if (abbr.contains('G')) ...['PG', 'SG'],
      if (abbr.contains('F')) ...['SF', 'PF'],
      if (abbr.contains('C')) 'C',
    ];

/// One page of the byathlete stats response -> season-total [Player]s (id =
/// ESPN athlete id) plus minutes per game by id.
({List<Player> players, Map<String, double> minutes}) parseStatsPage(Map<String, dynamic> json) {
  // Each athlete category's `totals` array lines up with the top-level category's `names`.
  final names = {
    for (final c in json['categories'] as List) c['name'] as String: (c['names'] as List).cast<String>(),
  };
  final players = <Player>[];
  final minutes = <String, double>{};
  for (final row in json['athletes'] as List) {
    final a = row['athlete'] as Map<String, dynamic>;
    final s = <String, double>{};
    for (final c in row['categories'] as List) {
      final keys = names[c['name']] ?? const [];
      final totals = c['totals'] as List;
      for (var i = 0; i < keys.length && i < totals.length; i++) {
        s[keys[i]] = double.tryParse('${totals[i]}'.replaceAll(',', '')) ?? 0;
      }
    }
    final id = a['id'] as String;
    players.add(Player(
      id: id,
      name: a['displayName'] as String,
      team: a['teamShortName'] as String? ?? '',
      eligiblePositions: espnPositions(a['position']?['abbreviation'] as String? ?? ''),
      gp: (s['gamesPlayed'] ?? 0).round(),
      fgPct: (s['fieldGoalPct'] ?? 0) / 100,
      fgAttempted: (s['fieldGoalsAttempted'] ?? 0).round(),
      ftPct: (s['freeThrowPct'] ?? 0) / 100,
      ftAttempted: (s['freeThrowsAttempted'] ?? 0).round(),
      threePM: (s['threePointFieldGoalsMade'] ?? 0).round(),
      pts: (s['points'] ?? 0).round(),
      reb: (s['rebounds'] ?? 0).round(),
      ast: (s['assists'] ?? 0).round(),
      stl: (s['steals'] ?? 0).round(),
      blk: (s['blocks'] ?? 0).round(),
      to: (s['turnovers'] ?? 0).round(),
      dataSource: DataSource.priorSeasonActual,
    ));
    minutes[id] = s['avgMinutes'] ?? 0;
  }
  return (players: players, minutes: minutes);
}

List<InjuryEntry> parseInjuries(Map<String, dynamic> json) {
  final out = <InjuryEntry>[];
  for (final team in json['injuries'] as List) {
    for (final i in team['injuries'] as List) {
      final a = i['athlete'] as Map<String, dynamic>;
      // The athlete object has no id field; it's only in the player-card link.
      final href = (a['links'] as List?)?.map((l) => l['href'] as String? ?? '').join(' ') ?? '';
      final id = RegExp(r'/id/(\d+)').firstMatch(href)?.group(1);
      if (id == null) continue;
      final d = i['details'] as Map<String, dynamic>? ?? const {};
      out.add(InjuryEntry(
        playerId: id,
        name: a['displayName'] as String,
        team: a['team']?['abbreviation'] as String? ?? '',
        position: a['position']?['abbreviation'] as String? ?? '',
        status: i['status'] as String,
        detail: [d['type'], d['detail']].whereType<String>().join(' '),
        returnDate: d['returnDate'] as String?,
      ));
    }
  }
  return out;
}

Future<Map<String, dynamic>> _getJson(String url) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) throw Exception('GET $url -> ${res.statusCode}');
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// ESPN labels a season by the year it ends (2026-27 -> 2027).
int currentSeason(DateTime now) => now.month >= 8 ? now.year + 1 : now.year;

Future<({List<Player> players, Map<String, double> minutes})> fetchStats(int season) async {
  final players = <Player>[];
  final minutes = <String, double>{};
  for (var page = 1;; page++) {
    final json = await _getJson('$_statsUrl&season=$season&page=$page');
    final parsed = parseStatsPage(json);
    players.addAll(parsed.players);
    minutes.addAll(parsed.minutes);
    if (page >= (json['pagination']?['pages'] as int? ?? 1)) break;
  }
  return (players: players, minutes: minutes);
}

Future<List<InjuryEntry>> fetchInjuries() async => parseInjuries(await _getJson(_injuriesUrl));
