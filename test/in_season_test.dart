import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosteriq/models/player.dart';
import 'package:rosteriq/models/stat_category.dart';
import 'package:rosteriq/screens/matchup_screen.dart';
import 'package:rosteriq/services/player_repository.dart';
import 'package:rosteriq/state/ranking_provider.dart';
import 'package:rosteriq/theme.dart';
import 'package:rosteriq/widgets/category_radar_chart.dart';

Map<String, dynamic> _json(String id, String name, {int gp = 5, int pts = 100}) => {
      'id': id,
      'name': name,
      'team': 'SAS',
      'eligiblePositions': ['C'],
      'gp': gp,
      'fgPct': 0.5,
      'fgAttempted': 80,
      'ftPct': 0.8,
      'ftAttempted': 30,
      'threePM': 10,
      'pts': pts,
      'reb': 50,
      'ast': 20,
      'stl': 5,
      'blk': 15,
      'to': 12,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mergeSnapshot', () {
    final bundled = [
      Player.fromJson({..._json('victor-wembanyama', 'Victor Wembanyama', gp: 70, pts: 1800), 'nbaId': 1641705, 'careerGpHistory': [71]}),
      Player.fromJson(_json('injured-guy', 'Injured Guy', gp: 60)),
    ];
    final snapshot = {
      'updatedAt': '2026-10-25T10:00:00Z',
      'players': [
        _json('5104157', 'Victor Wembanyama'),
        _json('999', 'Rookie Unknown'),
      ],
      'injuries': [
        {'playerId': '5104157', 'name': 'Victor Wembanyama', 'team': 'SAS', 'position': 'C', 'status': 'Day-To-Day', 'detail': 'Ankle'},
      ],
    };

    test('re-keys matched players to bundled ids, keeping headshot + career GP and live stats', () async {
      final config = (await loadLeagueData(client: MockClient((_) async => http.Response('', 500)))).config;
      final data = mergeSnapshot(bundled, config, snapshot);
      final byId = {for (final p in data.players) p.id: p};

      final wemby = byId['victor-wembanyama']!;
      expect(wemby.nbaId, 1641705);
      expect(wemby.careerGpHistory, [71]);
      expect(wemby.pts, 100); // live season-to-date, not the 1800 projection
      expect(byId['999']!.name, 'Rookie Unknown'); // unmatched keeps the ESPN id
      expect(byId['injured-guy']!.gp, 0); // not in snapshot: kept, zeroed
      expect(data.injuries['victor-wembanyama']!.status, 'Day-To-Day');
      expect(data.updatedAt, DateTime.utc(2026, 10, 25, 10));
    });

    test('injury-only players map to one player: rostered, badged, never a phantom free agent', () async {
      final config = (await loadLeagueData(client: MockClient((_) async => http.Response('', 500)))).config;
      final injury = {'team': 'GS', 'position': 'F', 'status': 'Out', 'detail': 'Knee'};
      final data = mergeSnapshot(
        [Player.fromJson({..._json('jimmy-butler-iii', 'Jimmy Butler III', gp: 60), 'team': 'GSW'})],
        config,
        {
          'updatedAt': '2026-10-25T10:00:00Z',
          'players': [_json('1', 'Some Player')],
          'injuries': [
            {...injury, 'playerId': '6430', 'name': 'Jimmy Butler'},
            {...injury, 'playerId': '777', 'name': 'Rookie Hurt'},
          ],
          'league': {
            'teams': [
              {'name': 'Alon Tip-Top', 'playerIds': ['6430', '777'], 'updatedAt': '2026-10-25T10:00:00Z'},
            ],
          },
        },
      );
      final ids = data.players.map((p) => p.id).toList();
      expect(data.remoteTeams.single.playerIds, ['jimmy-butler-iii', '777']);
      expect(ids.where((id) => id == 'jimmy-butler-iii'), hasLength(1)); // one zero-stat copy, no ESPN twin
      expect(data.injuries['jimmy-butler-iii']!.status, 'Out');
      final rookie = data.players.firstWhere((p) => p.id == '777');
      expect((rookie.name, rookie.team, rookie.gp), ('Rookie Hurt', 'GSW', 0));
    });

    test('falls back to initial + surname for OCR-garbled names, only when unambiguous', () async {
      final config = (await loadLeagueData(client: MockClient((_) async => http.Response('', 500)))).config;
      final data = mergeSnapshot(
        [
          Player.fromJson(_json('c-bryant', 'C. Bryant')),
          Player.fromJson(_json('josh-green', 'Josh Green')),
          Player.fromJson({..._json('terance-mann', 'Terance Mann'), 'team': 'BKN'}),
        ],
        config,
        {
          'updatedAt': '2026-10-25T10:00:00Z',
          'players': [
            {..._json('1', 'Carter Bryant'), 'team': 'SA'}, // ESPN code, mapped to SAS
            _json('2', 'Jalen Green'),
            _json('3', 'Javonte Green'),
            {..._json('4', 'Tre Mann'), 'team': 'WSH'}, // different player, different team
          ],
          'injuries': [],
        },
      );
      final byId = {for (final p in data.players) p.id: p};
      expect(byId.keys, containsAll(['c-bryant', '2', '3', 'josh-green', '4', 'terance-mann']));
      expect(byId.keys, isNot(contains('1')));
      expect(byId['c-bryant']!.team, 'SAS');
      expect(byId['4']!.team, 'WAS');
      expect(byId['terance-mann']!.gp, 0);
    });
  });

  group('loadLeagueData', () {
    test('falls back to bundled projections when the snapshot fetch fails', () async {
      final data = await loadLeagueData(client: MockClient((_) async => http.Response('nope', 404)));
      expect(data.updatedAt, isNull);
      expect(data.injuries, isEmpty);
      expect(data.players, isNotEmpty);
    });

    test('uses the snapshot when the fetch succeeds', () async {
      final body = jsonEncode({'updatedAt': '2026-10-25T10:00:00Z', 'players': [_json('1', 'Some Player')], 'injuries': []});
      final data = await loadLeagueData(client: MockClient((_) async => http.Response(body, 200)));
      expect(data.updatedAt, isNotNull);
    });
  });

  // Week 1 numbers from the user's Yahoo screenshots (FG% FT% 3PM PTS REB AST STL BLK TO).
  TeamWeek team(String name, List<double> v) =>
      (name: name, stats: {for (var i = 0; i < 9; i++) allStatCategories[i]: v[i]});
  final ironi = team('Ironi shaide', [.484, .758, 60, 542, 178, 106, 27, 14, 70]);
  final alon = team('Alon Tip-Top', [.497, .773, 50, 523, 192, 134, 29, 21, 86]);
  final henz = team('henz1k', [.452, .785, 48, 480, 166, 117, 25, 25, 67]);
  final white = team('The White Answer', [.454, .800, 63, 527, 157, 97, 35, 22, 90]);
  final week1 = [
    (week: 1, a: ironi, b: alon, updatedAt: DateTime.utc(2026)),
    (week: 1, a: henz, b: white, updatedAt: DateTime.utc(2026)),
  ];

  test('score matches Yahoo, with fewer turnovers winning TO', () {
    expect(score(ironi, alon), (w: 3, l: 6, t: 0));
    expect(score(henz, white), (w: 4, l: 5, t: 0));
    expect(categoryOutcome(StatCategory.to, 70, 86), CategoryOutcome.win);
    expect(categoryOutcome(StatCategory.pts, 500, 500), CategoryOutcome.tie);
  });

  test('leagueTable counts records and category wins per team', () {
    final rows = {for (final r in leagueTable(week1)) r.name: r};
    expect(rows['Ironi shaide']!.record, (w: 0, l: 1, t: 0));
    expect(rows['Ironi shaide']!.cats.w, 3);
    expect(rows['Alon Tip-Top']!.catWins[StatCategory.reb], 1);
    expect(rows['Alon Tip-Top']!.catWins[StatCategory.to], 0);
    expect(rows['The White Answer']!.record, (w: 1, l: 0, t: 0));
  });

  test('sideOf flips the matchup to my side', () {
    expect(sideOf(week1.first, 'Alon Tip-Top')!.opp.name, 'Ironi shaide');
    expect(sideOf(week1.last, 'Ironi shaide'), isNull);
    expect(formatStat(StatCategory.fgPct, .484), '.484');
    expect(formatStat(StatCategory.pts, 542), '542');
  });

  testWidgets('matchup table labels each result with text, not color alone', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: MatchupTable(a: ironi, b: alon, aLabel: 'YOU', bLabel: 'OPP')),
    ));
    expect(find.text('W'), findsNWidgets(3));
    expect(find.text('L'), findsNWidgets(6));
  });

  testWidgets('league table sorts by a tapped category', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: LeagueTable(rows: leagueTable(week1), myName: 'Ironi shaide')),
    ));
    expect(find.text('Ironi shaide'), findsOneWidget);
    await tester.tap(find.text('3PM'));
    await tester.pump();
    // The White Answer (63) and Ironi shaide (60) won 3PM; they now lead the table.
    final first = tester.getTopLeft(find.text('The White Answer')).dy;
    expect(first, lessThan(tester.getTopLeft(find.text('Alon Tip-Top')).dy));
  });

  test('leagueZ puts each team on the league scale, with fewer turnovers counting as better', () {
    final z = leagueZ(week1);
    expect(z['Ironi shaide']![StatCategory.pts]!, greaterThan(0)); // 542: most points of the four
    expect(z['The White Answer']![StatCategory.to]!, lessThan(0)); // 90 TO: the most
    expect(z['henz1k']![StatCategory.to]!, greaterThan(0)); // 67 TO: the fewest
  });

  testWidgets('standings rank teams by categories won and expand into splits', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Standings(rows: leagueTable(week1), period: week1, myName: 'Ironi shaide'),
        ),
      ),
    ));
    // Alon won 6 categories: first. Ironi won 3: last.
    final alonY = tester.getTopLeft(find.text('Alon Tip-Top')).dy;
    expect(alonY, lessThan(tester.getTopLeft(find.text('Ironi shaide (you)')).dy));
    expect(find.text('6-3-0'), findsOneWidget);
    await tester.tap(find.text('Alon Tip-Top'));
    await tester.pumpAndSettle();
    expect(find.text('Categories won'), findsOneWidget);
  });

  test('allPlay compares every team with every other team per category', () {
    final rows = {for (final r in allPlay(week1)) r.name: r};
    // Ironi shaide's 542 PTS beats all 3 other teams this week; TO 70 beats Alon (86) and White (90), loses to henz1k (67).
    expect(rows['Ironi shaide']!.cats[StatCategory.pts], (w: 3, l: 0, t: 0));
    expect(rows['Ironi shaide']!.cats[StatCategory.to], (w: 2, l: 1, t: 0));
    expect(allPlayRank(allPlay(week1), 'Ironi shaide', StatCategory.pts), 1);
    expect(rows['Ironi shaide']!.avg[StatCategory.pts], 542);
    expect(ordinal(1), '1st');
    expect(ordinal(12), '12th');
    expect(ordinal(22), '22nd');
  });

  testWidgets('radar renders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: CategoryRadarChart(standing: {for (final c in allStatCategories) c: 1.0}, puntedCategories: const {}),
      ),
    ));
    expect(find.byType(CategoryRadarChart), findsOneWidget);
  });

  test('likelyRosteredIds takes the top N by preseason rank and ignores unranked players', () {
    final players = [
      Player.fromJson({..._json('a', 'A'), 'sourceRank': 3}),
      Player.fromJson({..._json('b', 'B'), 'sourceRank': 1}),
      Player.fromJson({..._json('c', 'C'), 'sourceRank': 2}),
      Player.fromJson(_json('d', 'D')),
    ];
    expect(likelyRosteredIds(players, 2), {'b', 'c'});
  });
}
