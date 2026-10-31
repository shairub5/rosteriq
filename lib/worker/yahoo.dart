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

/// A page came back without what the parser expects (Yahoo changed its HTML). Nothing gets published.
class YahooParseError implements Exception {
  YahooParseError(this.message);
  final String message;
  @override
  String toString() => 'Yahoo page not understood: $message';
}

String _text(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The <table> that contains [needle].
String _tableAround(String html, String needle) {
  final at = html.indexOf(needle);
  final start = at < 0 ? -1 : html.lastIndexOf('<table', at);
  final end = at < 0 ? -1 : html.indexOf('</table>', at);
  if (start < 0 || end < 0) throw YahooParseError('no table with $needle');
  return html.substring(start, end);
}

/// League home: the team ids from the standings, the week shown and its matchup page paths.
({List<int> teamIds, int week, List<String> matchupPaths}) parseYahooLeague(String html) {
  final teamIds = {
    for (final m in RegExp(r'/nba/1623/(\d+)"').allMatches(_tableAround(html, 'id="standingstable"'))) int.parse(m[1]!),
  }.toList()
    ..sort();
  final paths = {
    for (final m in RegExp(r"data-target='(/nba/1623/matchup\?week=\d+&(?:amp;)?mid1=\d+&(?:amp;)?mid2=\d+)'").allMatches(html))
      m[1]!.replaceAll('&amp;', '&'),
  }.toList();
  if (teamIds.isEmpty || paths.isEmpty) throw YahooParseError('league page: ${teamIds.length} teams, ${paths.length} matchups');
  return (teamIds: teamIds, week: int.parse(RegExp(r'week=(\d+)').firstMatch(paths.first)![1]!), matchupPaths: paths);
}

/// A team's page: its name (from the title, "League - Team | Fantasy Basketball...") and every rostered player.
({String name, List<String> players}) parseYahooTeam(String html) {
  final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html)?[1] ?? '';
  final dash = title.indexOf(' - ');
  final bar = title.lastIndexOf(' | Fantasy');
  if (dash < 0 || bar < dash) throw YahooParseError('team page title');
  final players = [
    for (final m in RegExp(r'<a class="Nowrap name F-link[^"]*"[^>]*>([^<]+)</a>').allMatches(_tableAround(html, 'id="statTable0"')))
      _text(m[1]!),
  ];
  if (players.isEmpty) throw YahooParseError('team page has no players');
  return (name: _text(title.substring(dash + 3, bar)), players: players);
}

/// A matchup page: both teams' category totals plus games played / remaining ("32/43 Games Played").
/// [isFinal] marks a finished week with remaining = 0 so the app shows it as Won/Lost.
List<MatchupSide> parseYahooMatchup(String html, {bool isFinal = false}) {
  final rows = RegExp(r'<tr.*?</tr>', dotAll: true).allMatches(_tableAround(html, 'Field Goals Made/Field Goals Attempted')).skip(1).toList();
  if (rows.length != 2) throw YahooParseError('matchup table has ${rows.length} teams');
  final games = RegExp(r'id="remaining-games".*?</div>\s*</div>', dotAll: true).firstMatch(html)?[0] ?? '';
  final spans = [for (final m in RegExp(r'<span>([^<]*)</span>').allMatches(games)) m[1]!];
  num n(String s) => num.tryParse(s) ?? 0;
  return [
    for (final (i, row) in rows.indexed)
      () {
        final c = [for (final m in RegExp(r'<td.*?</td>', dotAll: true).allMatches(row[0]!)) _text(m[0]!)];
        if (c.length < 12) throw YahooParseError('matchup row has ${c.length} cells');
        final fg = c[1].split('/'), ft = c[3].split('/');
        final played = spans.length == 4 ? spans[i == 0 ? 1 : 2].split('/').first : '0';
        return (
          name: c[0],
          stats: <String, num>{
            'fgPct': n(c[2]), 'ftPct': n(c[4]), 'threePM': n(c[5]), 'pts': n(c[6]), 'reb': n(c[7]),
            'ast': n(c[8]), 'stl': n(c[9]), 'blk': n(c[10]), 'to': n(c[11]),
            'fgm': n(fg[0]), 'fga': n(fg.last), 'ftm': n(ft[0]), 'fta': n(ft.last),
            'gp': n(played),
            if (isFinal) 'remaining': 0 else if (spans.length == 4) 'remaining': n(spans[i == 0 ? 0 : 3]),
          },
        );
      }(),
  ];
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
