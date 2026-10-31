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
}
