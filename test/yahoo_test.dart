import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosteriq/worker/yahoo.dart';

void main() {
  http.Client answering(http.Response Function(http.Request) f) => MockClient((r) async => f(r));
  http.Response redirect(String to) => http.Response('', 302, headers: {'location': to});

  test('returns the page and sends the cookie', () async {
    final c = answering((r) {
      expect(r.headers['Cookie'], 'a=1');
      return http.Response('<html>', 200);
    });
    expect(await fetchYahooPage(c, '/nba/1623', 'a=1'), '<html>');
  });

  test('a redirect to login or consent means logged out', () async {
    for (final to in ['https://login.yahoo.com/?done=x', 'https://guce.yahoo.com/consent']) {
      await expectLater(fetchYahooPage(answering((_) => redirect(to)), '/nba/1623', 'a=1'), throwsA(isA<YahooLoggedOut>()));
    }
  });

  test('refusals are blocks, including the 999 rate limit', () async {
    for (final status in [401, 403, 429, 999]) {
      await expectLater(
        fetchYahooPage(answering((_) => http.Response('', status)), '/nba/1623', 'a=1'),
        throwsA(isA<YahooBlocked>().having((e) => e.status, 'status', status)),
      );
    }
  });

  test('follows a redirect within yahoo.com', () async {
    final c = answering((r) => r.url.path == '/nba/1623' ? redirect('/nba/1623/') : http.Response('ok', 200));
    expect(await fetchYahooPage(c, '/nba/1623', 'a=1'), 'ok');
  });

  test('never sends the cookie to another site', () async {
    var calls = 0;
    final c = answering((_) {
      calls++;
      return redirect('https://evil.example/');
    });
    await expectLater(fetchYahooPage(c, '/nba/1623', 'a=1'), throwsException);
    expect(calls, 1);
  });

  group('applyYahooData', () {
    final players = [(id: '1', name: 'Nikola Jokic'), (id: '2', name: 'Stephen Curry')];
    final now = DateTime.utc(2026, 11, 1);
    Map<String, dynamic> data(String at) => {
          'fetchedAt': at,
          'teams': [
            {'name': 'IRONI SHAIDE', 'players': ['Nikola Jokic']},
            {'name': 'Rivals', 'players': ['Stephen Curry']},
            {'name': 'Broken parse', 'players': ['Nobody Known']},
          ],
          'matchups': [
            {'week': 3, 'teams': [{'name': 'A', 'stats': {'pts': 1}}, {'name': 'B', 'stats': {'pts': 2}}]},
          ],
        };
    final league = <String, dynamic>{
      'myName': 'Ironi shaide',
      'teams': [
        {'name': 'My Team', 'playerIds': ['2'], 'updatedAt': 'old'},
        {'name': 'Broken parse', 'playerIds': ['2'], 'updatedAt': 'old'},
      ],
      'matchups': <dynamic>[],
    };

    test('updates rosters and matchups, my team stays "My Team", an empty roster is not wiped', () {
      final out = applyYahooData(league, data('t1'), players, now);
      final teams = {for (final t in out['teams'] as List) t['name']: t['playerIds']};
      expect(teams, {'My Team': ['1'], 'Broken parse': ['2'], 'Rivals': ['2']});
      expect((out['matchups'] as List).single['week'], 3);
      expect(out['yahooSyncedAt'], 't1');
    });

    test('applies each file once', () {
      final done = {...league, 'yahooSyncedAt': 't1'};
      expect(identical(applyYahooData(done, data('t1'), players, now), done), isTrue);
    });
  });

  // Trimmed from real pages (state/yahoo_dump), personal details removed.
  group('parsers', () {
    test('league: team ids, week and matchup paths', () {
      const html = '''<table id="standingstable"><a href="https://basketball.fantasysports.yahoo.com/nba/1623/2">A</a>
<a href="/nba/1623/10">B</a></table>
<li class='Linkable' data-target='/nba/1623/matchup?week=2&mid1=1&mid2=6'></li>
<li class='Linkable' data-target='/nba/1623/matchup?week=2&mid1=2&mid2=5'></li>''';
      final l = parseYahooLeague(html);
      expect(l.teamIds, [2, 10]);
      expect(l.week, 2);
      expect(l.matchupPaths, ['/nba/1623/matchup?week=2&mid1=1&mid2=6', '/nba/1623/matchup?week=2&mid1=2&mid2=5']);
    });

    test('team: name from the title, players from the roster table only', () {
      const html = '''<title>Jerusalem fantasy league - Ja&#39;Yoshay | Fantasy Basketball | Yahoo! Sports</title>
<a class="Nowrap name F-link" href="#">Outside Table</a>
<table class="x" id="statTable0"><tr><td><a class="Nowrap name F-link playernote" href="#" title="VJ Edgecombe">VJ Edgecombe</a></td></tr>
<tr><td><a class="Nowrap name F-link" href="#">Jaime Jaquez Jr.</a></td></tr></table>''';
      final t = parseYahooTeam(html);
      expect(t.name, "Ja'Yoshay");
      expect(t.players, ['VJ Edgecombe', 'Jaime Jaquez Jr.']);
    });

    const matchup = '''<div id="remaining-games" class="Py-lg"><div class="W-100">
<div class="Ta-start"><span>11</span> <span class="F-shade">Remaining</span></div>
<div class="Ta-c"><span>32/43</span> <span class="F-shade">Games Played</span> <span>33/41</span></div>
<div class="Ta-end"><span class="F-shade">Remaining</span> <span>8</span></div>
</div></div>
<table class="Datatable"><thead><tr class="First Last"><th title="Field Goals Made/Field Goals Attempted">FGM/A*</th></tr></thead><tbody>
<tr class="First"><td><a href="/nba/1623/1"><img></a><span><a href="/nba/1623/1">Ironi shaide</a></span></td><td><div>203/417</div></td><td><div>.487</div></td><td><div>90/115</div></td><td><div>.783</div></td><td><div>62</div></td><td><div>558</div></td><td><div>242</div></td><td><div>93</div></td><td><div>25</div></td><td><div>19</div></td><td><div>63</div></td><td><div>6</div></td></tr>
<tr><td><a href="/nba/1623/6">Kong-fu basket</a></td><td>201/460</td><td>.437</td><td>-/-</td><td>-</td><td>58</td><td>556</td><td>187</td><td>146</td><td>35</td><td>19</td><td>73</td><td>2</td></tr>
</tbody></table>''';

    test('matchup: totals for both teams, games played and remaining', () {
      final m = parseYahooMatchup(matchup);
      expect(m[0].name, 'Ironi shaide');
      expect(m[0].stats, {
        'fgPct': .487, 'ftPct': .783, 'threePM': 62, 'pts': 558, 'reb': 242, 'ast': 93, 'stl': 25, 'blk': 19, 'to': 63,
        'fgm': 203, 'fga': 417, 'ftm': 90, 'fta': 115, 'gp': 32, 'remaining': 11,
      });
      expect(m[1].name, 'Kong-fu basket');
      expect(m[1].stats['ftm'], 0); // "-/-" before any attempts
      expect(m[1].stats['gp'], 33);
      expect(m[1].stats['remaining'], 8);
    });

    test('a finished week has remaining = 0', () {
      expect(parseYahooMatchup(matchup, isFinal: true)[0].stats['remaining'], 0);
    });

    test('an unrecognized page is an error, never empty data', () {
      expect(() => parseYahooLeague('<html>'), throwsA(isA<YahooParseError>()));
      expect(() => parseYahooTeam('<title>x</title>'), throwsA(isA<YahooParseError>()));
      expect(() => parseYahooMatchup('<html>'), throwsA(isA<YahooParseError>()));
    });
  });
}
