// Fantrax league rosters from the public (no-login) API. A league opts in with
// `fantraxLeagueId` in the snapshot; the worker refreshes its teams twice a day.
// Matchup stats aren't public (fxpa answers NOT_LOGGED_IN), so those stay on screenshots.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'espn.dart';
import 'league_bot.dart';

const _base = 'https://www.fantrax.com/fxea/general';

/// Minimum gap between syncs: the cron fires every 2-3 h, so this lands about twice a day.
const fantraxSyncEvery = Duration(hours: 11);

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

bool fantraxSyncDue(Map<String, dynamic> league, DateTime now) {
  if (league['fantraxLeagueId'] == null) return false;
  final last = DateTime.tryParse(league['fantraxSyncedAt'] as String? ?? '');
  return last == null || now.difference(last) >= fantraxSyncEvery;
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

Future<Map<String, dynamic>> _getJson(String url) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) throw Exception('GET $url -> ${res.statusCode}');
  return jsonDecode(res.body) as Map<String, dynamic>;
}
