import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/worker/alerts.dart';
import 'package:rosteriq/worker/espn.dart';

Player _p(String id, String team, List<String> pos) => Player(
      id: id,
      name: 'P$id',
      team: team,
      eligiblePositions: pos,
      gp: 2,
      fgPct: 0.5,
      fgAttempted: 20,
      ftPct: 0.8,
      ftAttempted: 10,
      threePM: 4,
      pts: 30,
      reb: 10,
      ast: 6,
      stl: 2,
      blk: 1,
      to: 4,
    );

InjuryEntry _inj(String id, String status, {String team = 'DAL', String pos = 'G'}) => InjuryEntry(
      playerId: id,
      name: 'P$id',
      team: team,
      position: pos,
      status: status,
      detail: 'Ankle Sprain',
    );

void main() {
  test('parseStatsPage maps ESPN totals onto Player by category names', () {
    final page = parseStatsPage({
      'categories': [
        {'name': 'general', 'names': ['gamesPlayed', 'avgMinutes', 'rebounds']},
        {
          'name': 'offensive',
          'names': ['points', 'fieldGoalPct', 'fieldGoalsAttempted', 'freeThrowPct', 'freeThrowsAttempted',
              'threePointFieldGoalsMade', 'assists', 'turnovers'],
        },
        {'name': 'defensive', 'names': ['steals', 'blocks']},
      ],
      'athletes': [
        {
          'athlete': {'id': '42', 'displayName': 'Ty Jerome', 'teamShortName': 'MEM', 'position': {'abbreviation': 'G'}},
          'categories': [
            {'name': 'general', 'totals': ['2', '31.5', '9']},
            {'name': 'offensive', 'totals': ['1,073', '59.6', '47', '75.0', '12', '8', '11', '5']},
            {'name': 'defensive', 'totals': ['1', '1']},
          ],
        },
      ],
    });
    final p = page.players.single;
    expect(p.id, '42');
    expect(p.eligiblePositions, ['PG', 'SG']);
    expect(p.pts, 1073); // thousands separator stripped
    expect(p.fgPct, closeTo(0.596, 1e-9));
    expect(p.reb, 9);
    expect(page.minutes['42'], 31.5);
  });

  test('parseInjuries takes the athlete id from the player-card link', () {
    final list = parseInjuries({
      'injuries': [
        {
          'injuries': [
            {
              'status': 'Out',
              'athlete': {
                'displayName': 'Mouhamed Gueye',
                'links': [{'href': 'https://www.espn.com/nba/player/_/id/4712863/mouhamed-gueye'}],
                'team': {'abbreviation': 'ATL'},
                'position': {'abbreviation': 'F'},
              },
              'details': {'type': 'Foot', 'detail': 'Fracture', 'returnDate': '2026-11-20'},
            },
          ],
        },
      ],
    });
    expect(list.single.playerId, '4712863');
    expect(list.single.detail, 'Foot Fracture');
    expect(list.single.returnDate, '2026-11-20');
  });

  group('injuryAlerts', () {
    final pool = [_p('1', 'DAL', ['PG', 'SG']), _p('2', 'DAL', ['PG', 'SG']), _p('3', 'DAL', ['C']), _p('4', 'BOS', ['PG'])];
    List<String> run(Map<String, InjuryEntry> prev, Map<String, InjuryEntry> now, {Set<String>? relevant}) =>
        injuryAlerts(
          prev: prev,
          now: now,
          relevantIds: relevant ?? {'1', '2', '3', '4'},
          pool: pool,
          totalZById: {'2': 1.0, '3': 5.0, '4': 9.0},
          minutes: {'1': 30, '2': 25, '3': 30, '4': 30},
        );

    test('new Out lists same-team, same-position fill-ins only', () {
      final alerts = run({}, {'1': _inj('1', 'Out')});
      expect(alerts.single, contains('🚑 OUT: P1'));
      expect(alerts.single, contains('P2')); // DAL guard
      expect(alerts.single, isNot(contains('P3'))); // DAL center
      expect(alerts.single, isNot(contains('P4'))); // BOS guard
    });

    test('unchanged status is not re-sent', () {
      expect(run({'1': _inj('1', 'Out')}, {'1': _inj('1', 'Out')}), isEmpty);
    });

    test('status change and recovery both alert', () {
      expect(run({'1': _inj('1', 'Day-To-Day')}, {'1': _inj('1', 'Out')}).single, contains('OUT'));
      expect(run({'1': _inj('1', 'Out')}, {}).single, contains('✅ BACK: P1'));
    });

    test('irrelevant players are ignored', () {
      expect(run({}, {'1': _inj('1', 'Out')}, relevant: {'2'}), isEmpty);
    });
  });

  group('keepAliveReminder', () {
    final now = DateTime.utc(2027, 1, 1);
    test('quiet before day 50, nags from day 50, at most once a day', () {
      expect(keepAliveReminder(now: now, lastCommit: now.subtract(const Duration(days: 49))), isNull);
      expect(keepAliveReminder(now: now, lastCommit: now.subtract(const Duration(days: 52))), contains('52 days'));
      expect(
        keepAliveReminder(
          now: now,
          lastCommit: now.subtract(const Duration(days: 52)),
          lastReminder: now.subtract(const Duration(hours: 3)),
        ),
        isNull,
      );
    });
  });
}
