import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rosteriq/engine/matchup_needs.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/models/stat_category.dart';
import 'package:rosteriq/services/player_repository.dart';
import 'package:rosteriq/services/schedule_service.dart';
import 'package:rosteriq/worker/espn.dart';

final _schedule = NbaSchedule.fromJson(jsonDecode(File('assets/data/nba_schedule.json').readAsStringSync()) as Map<String, dynamic>);

Player _p(String id, {String team = 'IND', int gp = 10, int pts = 150, int stl = 10, int to = 20, int fga = 120, double fg = .47}) =>
    Player.fromJson({
      'id': id, 'name': 'P$id', 'team': team, 'eligiblePositions': ['G'], 'gp': gp, //
      'fgPct': fg, 'fgAttempted': fga, 'ftPct': .8, 'ftAttempted': 30, 'threePM': 20,
      'pts': pts, 'reb': 50, 'ast': 30, 'stl': stl, 'blk': 5, 'to': to,
    });

NightLine _line(String id, {int pts = 15, String team = 'IND', double min = 30}) => (
      id: id, name: 'P$id', team: team, min: min, pts: pts, reb: 5, ast: 3, threePM: 2, //
      stl: 1, blk: 0, to: 1, fgm: 6, fga: 12, ftm: 2, fta: 2,
    );

void main() {
  test('fantasyWeekDates: Monday-Sunday weeks from the opener\'s week', () {
    expect(fantasyWeekDates(1, _schedule), (start: DateTime(2026, 10, 19), end: DateTime(2026, 10, 25)));
    expect(fantasyWeekDates(5, _schedule), (start: DateTime(2026, 11, 16), end: DateTime(2026, 11, 22)));
  });

  test('weekGames counts real games before today, the schedule after', () {
    final p = _p('a', team: 'POR');
    final range = fantasyWeekDates(5, _schedule);
    final sched = _schedule.teams['POR']!.games.where((d) => !d.isBefore(range.start) && !d.isAfter(range.end)).toList();
    // He played only the first of the week's games; the rest were before "today" with box scores.
    final played = {for (final d in sched) DateTime(d.year, d.month, d.day): d == sched.first ? {'a'} : <String>{}};
    final g = weekGames(p, range, _schedule, played, today: DateTime(2026, 11, 23));
    expect((g.played, g.missed, g.left), (1, sched.length - 1, 0));
    // Mid-week: games from today on are "left"; nights without box scores count as played.
    final mid = weekGames(p, range, _schedule, const {}, today: DateTime(2026, 11, 19));
    expect(mid.played + mid.left, sched.length);
  });

  test('categoryNeeds: toss-up, chase, hold, safe, out of reach (fewer TO wins)', () {
    final me = {for (final c in allStatCategories) c: 100.0}..[StatCategory.fgPct] = .480;
    final opp = {...me, StatCategory.pts: 104.0, StatCategory.reb: 108.0, StatCategory.ast: 92.0, StatCategory.stl: 60.0, StatCategory.to: 80.0, StatCategory.fgPct: .475};
    final n = categoryNeeds(me, opp);
    expect(n[StatCategory.fgPct], Need.tossUp);
    expect(n[StatCategory.pts], Need.tossUp); // within 5%
    expect(n[StatCategory.reb], Need.chase);
    expect(n[StatCategory.ast], Need.hold);
    expect(n[StatCategory.stl], Need.safe);
    expect(n[StatCategory.to], Need.lost); // 100 vs 80 turnovers
  });

  test('hotNights: big night vs usual, with hurt teammates as the reason', () {
    final pool = [for (var i = 0; i < 40; i++) _p('x$i', pts: 80 + i * 5)];
    final quiet = _p('q', pts: 100); // 10 a game
    final star = _p('s', pts: 250);
    final night = (
      date: DateTime(2026, 11, 22),
      lines: {'q': _line('q', pts: 31), 's': _line('s', pts: 25)},
      outByTeam: {'IND': {'h', 'bench'}},
    );
    final byId = {for (final p in [...pool, quiet, star, _p('h', pts: 200)]) p.id: p};
    final hot = hotNights(
      night: night,
      candidates: [quiet, star],
      baseline: PerGameBaseline.of(pool, {for (final p in pool) p.id: 25.0}),
      playersById: byId,
      minutes: {'h': 34, 'bench': 8, 'q': 20},
    );
    expect(hot.map((h) => h.player.id), ['q']);
    expect(hot.single.boost, ['Ph']); // the 8-minute guy isn't a reason
  });

  test('dropCandidates: weakest first, an injured star is a stash not a drop', () {
    final pool = [for (var i = 0; i < 40; i++) _p('x$i', pts: 80 + i * 5)];
    final roster = [_p('star', pts: 300, stl: 20), _p('mid', pts: 180), _p('weak', pts: 60, stl: 2, fg: .38, fga: 110)];
    final drops = dropCandidates(
      roster: roster,
      baseline: PerGameBaseline.of(pool, {for (final p in pool) p.id: 25.0}),
      weights: {for (final c in allStatCategories) c: 1},
      needs: {for (final c in allStatCategories) c: Need.chase},
      injuries: {
        'star': const InjuryEntry(playerId: 'star', name: 'Pstar', team: 'IND', position: 'G', status: 'Out', detail: '', returnDate: '2026-12-20'),
      },
      gamesLeft: {'star': 3, 'mid': 3, 'weak': 1},
      today: DateTime(2026, 11, 23),
    );
    expect(drops.map((d) => d.player.id), ['weak', 'mid']);
    expect(drops.first.reasons, containsAll(['38.0% FG', '1 game left this week']));
  });

  test('teamWeekGames: daily lineups count starters only, and keep players dropped mid-week', () {
    final range = fantasyWeekDates(5, _schedule);
    DateTime gameDay(String team, int i) => _schedule.teams[team]!.games.where((d) => !d.isBefore(range.start)).elementAt(i);
    final kept = _p('kept', team: 'POR'), dropped = _p('gone', team: 'MIL');
    final d0 = gameDay('POR', 0), d1 = gameDay('MIL', 0);
    final lineups = {
      DateTime(d0.year, d0.month, d0.day): <LineupSlot>[(id: 'kept', slot: 'BN', min: 30), (id: 'gone', slot: 'SF', min: _schedule.teams['MIL']!.hasGameOn(d0) ? 25 : null)],
      DateTime(d1.year, d1.month, d1.day): <LineupSlot>[(id: 'gone', slot: 'Util', min: 28)],
    };
    final rows = teamWeekGames(
      roster: [kept],
      playersById: {'kept': kept, 'gone': dropped},
      lineups: lineups,
      range: range,
      schedule: _schedule,
      played: const {},
      today: DateTime(2026, 11, 23),
    );
    final k = rows.firstWhere((r) => r.player.id == 'kept');
    final g = rows.firstWhere((r) => r.player.id == 'gone');
    expect(k.benched, 1); // a bench game doesn't count
    expect(g.onRoster, isFalse);
    expect(g.games.played, greaterThanOrEqualTo(1));
  });
}
