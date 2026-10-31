// Yahoo league pages (bin/yahoo_sync.dart), fetched from the user's own Mac with their login cookie so
// the requests come from their usual IP. Read-only GETs, no retries, no automated login: any sign that
// Yahoo is unhappy stops the run and leaves a marker that blocks later runs until a person looks at it.
import 'package:http/http.dart' as http;

import 'espn.dart';
import 'league_bot.dart';

const yahooBase = 'https://basketball.fantasysports.yahoo.com';
const _userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/130.0.0.0 Safari/537.36';

/// Yahoo wants a login or a consent page: the cookie expired or was signed out.
class YahooLoggedOut implements Exception {
  @override
  String toString() => 'Yahoo cookie is not logged in';
}

/// Yahoo refused the request (401/403/429, or its 999 rate-limit status).
class YahooBlocked implements Exception {
  YahooBlocked(this.status);
  final int status;
  @override
  String toString() => 'Yahoo refused the request (HTTP $status)';
}

/// One page's HTML. Follows redirects by hand so the cookie only ever goes to yahoo.com hosts.
Future<String> fetchYahooPage(http.Client client, String path, String cookie) async {
  var url = Uri.parse('$yahooBase$path');
  for (var hop = 0; hop < 3; hop++) {
    final req = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll({'Cookie': cookie, 'User-Agent': _userAgent, 'Accept': 'text/html'});
    final res = await http.Response.fromStream(await client.send(req));
    if (res.statusCode == 200) return res.body;
    if (res.statusCode >= 300 && res.statusCode < 400) {
      final next = url.resolve(res.headers['location'] ?? '');
      if (next.host.startsWith('login.') || next.host.startsWith('guce.') || next.host.startsWith('consent.')) {
        throw YahooLoggedOut();
      }
      if (next.scheme != 'https' || !next.host.endsWith('.yahoo.com')) throw Exception('Yahoo redirected to ${next.host}');
      url = next;
      continue;
    }
    if (const {401, 403, 429, 999}.contains(res.statusCode)) throw YahooBlocked(res.statusCode);
    throw Exception('Yahoo $path -> ${res.statusCode}');
  }
  throw Exception('Yahoo $path: too many redirects');
}

/// Merges yahoo.json (published by the Mac to the `yahoo` branch) into the league:
///   {fetchedAt, teams: [{name, players: [full names]}], matchups: [{week, teams: [{name, stats}]}]}
/// Each file is applied once, so a later screenshot isn't overwritten by an older fetch. A roster with
/// no matched players is skipped rather than wiping the team; `myName` becomes "My Team".
Map<String, dynamic> applyYahooData(
  Map<String, dynamic> league,
  Map<String, dynamic> data,
  List<({String id, String name})> players,
  DateTime now,
) {
  if (league['yahooSyncedAt'] == data['fetchedAt']) return league;
  var teams = [...((league['teams'] as List?) ?? const []).cast<Map<String, dynamic>>()];
  final myName = normalizeName(league['myName'] as String? ?? '');
  for (final t in (data['teams'] as List).cast<Map<String, dynamic>>()) {
    final ids = matchRosterNames((t['players'] as List).cast<String>(), players).ids;
    if (ids.isEmpty) continue;
    final name = t['name'] as String;
    teams = upsertTeam(teams, normalizeName(name) == myName ? 'My Team' : name, ids, now);
  }
  var matchups = [...((league['matchups'] as List?) ?? const []).cast<Map<String, dynamic>>()];
  for (final m in (data['matchups'] as List).cast<Map<String, dynamic>>()) {
    matchups = upsertMatchup(matchups, {...m, 'updatedAt': now.toIso8601String()});
  }
  return {...league, 'teams': teams, 'matchups': matchups, 'yahooSyncedAt': data['fetchedAt']};
}
