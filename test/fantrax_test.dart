import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/worker/cookies.dart';
import 'package:rosteriq/worker/fantrax.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  test('parseFantraxRosters flips "Last, First" and skips unknown ids', () {
    final r = parseFantraxRosters({
      'rosters': {
        't1': {
          'teamName': 'Shaide',
          'rosterItems': [
            {'id': 'a'},
            {'id': 'zz'},
          ],
        },
      },
    }, {
      'a': {'name': 'Maxey, Tyrese'},
    });
    expect(r.single.team, 'Shaide');
    expect(r.single.names, ['Tyrese Maxey']);
  });

  test('applyFantraxRosters stores my team as My Team and stamps the sync', () {
    final l = applyFantraxRosters(
      {'myName': 'Shaide', 'teams': []},
      [
        (team: 'Shaide', names: ['Tyrese Maxey']),
        (team: 'Lior', names: ['Jaren Jackson']),
      ],
      [(id: '1', name: 'Tyrese Maxey'), (id: '2', name: 'Jaren Jackson Jr.')],
      now,
    );
    expect([for (final t in l['teams']) '${t['name']}: ${t['playerIds']}'], ['My Team: [1]', 'Lior: [2]']);
    expect(l['fantraxSyncedAt'], now.toIso8601String());
  });

  test('currentScoringPeriod reads Fantrax offsets without a colon', () {
    final info = {
      'scoringPeriods': [
        {'number': 1, 'startDate': '2026-10-20T15:00:00.0-0400', 'endDate': '2026-10-26T18:59:59.0-0400'},
        {'number': 2, 'startDate': '2026-10-26T19:00:00.0-0400', 'endDate': '2026-11-02T18:59:59.0-0500'},
      ],
    };
    expect(currentScoringPeriod(info, DateTime.utc(2026, 10, 26, 22)), 1); // 18:00 ET Mon
    expect(currentScoringPeriod(info, DateTime.utc(2026, 10, 27)), 2);
    expect(currentScoringPeriod(info, DateTime.utc(2026, 12)), isNull);
  });

  test('isFantraxLoggedOut spots the not-logged-in answer', () {
    expect(isFantraxLoggedOut({'pageError': {'code': 'WARNING_NOT_LOGGED_IN'}}), isTrue);
    expect(isFantraxLoggedOut({'responses': []}), isFalse);
  });

  test('cookies round-trip through AES-GCM and never store the plain text', () async {
    final key = base64.encode(List.generate(32, (i) => i));
    final sealed = await encryptCookie('JSESSIONID=abc; FX_RM=xyz', key);
    expect(sealed, isNot(contains('JSESSIONID')));
    expect(await decryptCookie(sealed, key), 'JSESSIONID=abc; FX_RM=xyz');
    expect(cookieState(null), 'missing');
    expect(cookieState(cookieEntry(sealed, now)), 'ok');
    expect(cookieState({...cookieEntry(sealed, now), 'expiredAt': now.toIso8601String()}), 'expired');
  });
}
