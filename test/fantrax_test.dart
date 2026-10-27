import 'package:flutter_test/flutter_test.dart';
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

  test('fantraxSyncDue: only opted-in leagues, about twice a day', () {
    expect(fantraxSyncDue({}, now), isFalse);
    expect(fantraxSyncDue({'fantraxLeagueId': 'x'}, now), isTrue);
    Map<String, dynamic> at(Duration ago) =>
        {'fantraxLeagueId': 'x', 'fantraxSyncedAt': now.subtract(ago).toIso8601String()};
    expect(fantraxSyncDue(at(const Duration(hours: 3)), now), isFalse);
    expect(fantraxSyncDue(at(const Duration(hours: 11)), now), isTrue);
  });
}
