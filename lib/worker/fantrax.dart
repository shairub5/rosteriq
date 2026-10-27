// Fantrax sync (bin/fantrax_sync.dart, twice a day) for any league with `fantraxLeagueId` in the snapshot.
// Rosters come from the public (no-login) fxea API. Live scoring needs the user's login cookie
// (sent to the bot with /fantrax_cookie); without it fxpa answers NOT_LOGGED_IN.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'espn.dart';
import 'league_bot.dart';

const _base = 'https://www.fantrax.com/fxea/general';
const _userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/130.0.0.0 Safari/537.36';

/// The cookie no longer logs in (expired or signed out).
class FantraxLoggedOut implements Exception {
  @override
  String toString() => 'Fantrax cookie is not logged in';
}

/// getTeamRosters + getPlayerIds -> one entry per team, player names as "First Last".
List<({String team, List<String> names})> parseFantraxRosters(
  Map<String, dynamic> rosters,
  Map<String, dynamic> playerIds,
) => [
      for (final t in (rosters['rosters'] as Map<String, dynamic>).values)
        (
          team: t['teamName'] as String,
          names: [
            for (final r in (t['rosterItems'] as List))
              if (playerIds[r['id']]?['name'] case final String n) _firstLast(n),
          ],
        ),
    ];

/// Fantrax writes "Porter, Michael".
String _firstLast(String n) {
  final i = n.indexOf(', ');
  return i < 0 ? n : '${n.substring(i + 2)} ${n.substring(0, i)}';
}

/// Replaces the league's teams with the Fantrax rosters; `myName` becomes "My Team".
Map<String, dynamic> applyFantraxRosters(
  Map<String, dynamic> league,
  List<({String team, List<String> names})> rosters,
  List<({String id, String name})> players,
  DateTime now,
) {
  var teams = [...((league['teams'] as List?) ?? const []).cast<Map<String, dynamic>>()];
  final myName = normalizeName(league['myName'] as String? ?? '');
  for (final r in rosters) {
    final name = normalizeName(r.team) == myName ? 'My Team' : r.team;
    teams = upsertTeam(teams, name, matchRosterNames(r.names, players).ids, now);
  }
  return {...league, 'teams': teams, 'fantraxSyncedAt': now.toIso8601String()};
}

Future<List<({String team, List<String> names})>> fetchFantraxRosters(String leagueId) async =>
    parseFantraxRosters(
      await _getJson('$_base/getTeamRosters?leagueId=$leagueId'),
      await _getJson('$_base/getPlayerIds?sport=NBA'),
    );

Future<Map<String, dynamic>> fetchFantraxLeagueInfo(String leagueId) =>
    _getJson('$_base/getLeagueInfo?leagueId=$leagueId');

/// Scoring period (matchup week) number containing [now], from getLeagueInfo; null off-season.
int? currentScoringPeriod(Map<String, dynamic> leagueInfo, DateTime now) {
  for (final p in (leagueInfo['scoringPeriods'] as List).cast<Map<String, dynamic>>()) {
    if (!now.isBefore(_fantraxDate(p['startDate'] as String)) && now.isBefore(_fantraxDate(p['endDate'] as String))) {
      return p['number'] as int;
    }
  }
  return null;
}

/// The week that ended within the last day, so a twice-daily run stores its final totals once.
int? justEndedScoringPeriod(Map<String, dynamic> leagueInfo, DateTime now) {
  for (final p in (leagueInfo['scoringPeriods'] as List).cast<Map<String, dynamic>>()) {
    final end = _fantraxDate(p['endDate'] as String);
    if (!now.isBefore(end) && now.difference(end) < const Duration(days: 1)) return p['number'] as int;
  }
  return null;
}

/// "2026-10-26T18:59:59.0-0400" (no colon in the offset) -> UTC.
DateTime _fantraxDate(String s) => DateTime.parse(s.replaceFirstMapped(RegExp(r'([+-]\d\d)(\d\d)$'), (m) => '${m[1]}:${m[2]}'));

/// One logged-in fxpa call; returns the first response's `data`. Throws [FantraxLoggedOut].
Future<Map<String, dynamic>> fantraxRequest(
  String leagueId,
  String cookie,
  String method,
  Map<String, dynamic> data,
) async {
  final res = await http.post(
    Uri.parse('https://www.fantrax.com/fxpa/req?leagueId=$leagueId'),
    headers: {'Content-Type': 'application/json', 'Cookie': cookie, 'User-Agent': _userAgent},
    body: jsonEncode({
      'msgs': [
        {'method': method, 'data': {'leagueId': leagueId, ...data}},
      ],
    }),
  );
  if (res.statusCode == 401 || res.statusCode == 403) throw FantraxLoggedOut();
  if (res.statusCode != 200) throw Exception('Fantrax $method -> ${res.statusCode}');
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final first = (j['responses'] as List?)?.firstOrNull as Map<String, dynamic>?;
  if (isFantraxLoggedOut(j) || first?['data'] == null) throw FantraxLoggedOut();
  return first!['data'] as Map<String, dynamic>;
}

bool isFantraxLoggedOut(Map<String, dynamic> response) =>
    (response['pageError'] as Map?)?['code'] == 'WARNING_NOT_LOGGED_IN';

/// Live category totals for one scoring period (the whole matchup week).
Future<Map<String, dynamic>> fetchFantraxLiveScoring(String leagueId, String cookie, int period) =>
    fantraxRequest(leagueId, cookie, 'getLiveScoringStats', {
      'newView': true,
      'period': '$period',
      'playerViewType': '1',
      'sppId': '-1',
      'viewType': '2', // Period (the whole matchup week); '1' is a single day
    });

/// Fantrax scoring-category ids -> the app's stat keys (`statKeys`).
const _fantraxCats = {
  '1520': 'fgPct',
  '1550': 'ftPct',
  '1435': 'threePM',
  '1390': 'pts',
  '1400': 'reb',
  '1250': 'ast',
  '1410': 'stl',
  '1260': 'blk',
  '1460': 'to',
};

/// Period-view live scoring -> each matchup's two sides with the 9 category totals.
/// A team's totals are the `_3010` (player group) row of its ACTIVE stats. [isFinal] adds
/// remaining = 0 so the app shows the week as Won/Lost; while it's live, remaining is left out
/// (Fantrax doesn't give games left), which the app treats as "in progress".
List<List<MatchupSide>> parseFantraxLiveScoring(Map<String, dynamic> data, {bool isFinal = false}) {
  final names = {for (final t in (data['fantasyTeams'] as List)) t['id'] as String: t['name'] as String};
  final teams = (data['statsPerTeam'] as Map)['allTeamsStats'] as Map<String, dynamic>;
  MatchupSide side(String id) {
    final row = (((teams[id] as Map)['ACTIVE'] as Map)['statsMap'] as Map)['_3010'] as Map;
    return (
      name: names[id] ?? id,
      stats: {
        for (final c in (row['object2'] as List).cast<Map<String, dynamic>>())
          ?_fantraxCats[(c['scipId'] as String).split('#')[1]]: c['av'] as num,
        if (isFinal) 'remaining': 0,
      },
    );
  }

  return [
    for (final m in (data['matchups'] as List).cast<String>())
      if (m.split('_') case [final away, final home]) [side(away), side(home)],
  ];
}

/// True when [cookie] gets live scoring for the current (or first) week.
Future<bool> fantraxCookieWorks(String leagueId, String cookie) async {
  try {
    final period = currentScoringPeriod(await fetchFantraxLeagueInfo(leagueId), DateTime.now()) ?? 1;
    await fetchFantraxLiveScoring(leagueId, cookie, period);
    return true;
  } on FantraxLoggedOut {
    return false;
  }
}

Future<Map<String, dynamic>> _getJson(String url) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) throw Exception('GET $url -> ${res.statusCode}');
  return jsonDecode(res.body) as Map<String, dynamic>;
}
